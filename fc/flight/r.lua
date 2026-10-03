-- Resection using a magnetized (always-north) navtable for exact
-- heading, plus three anchor navtables for position, on a tilting raft.
--
-- Modeled directly from game source:
--   - GimbalSensorBlockEntity: XAngle = atan2(ld.z, -ld.y),
--     ZAngle = atan2(ld.x, -ld.y), ld = world-down in the contraption's
--     local frame. The CC script reads roll = -XAngle(deg), pitch =
--     -ZAngle(deg).
--   - NavTableBlockEntity: relativeAngle = atan2(localDir.z, localDir.x)
--     of a world-space line-of-sight transformed into that same local
--     frame -- this is what getRelativeAngle() returns, for anchors AND
--     for the magnetized table (whose target is always true north).
--
-- Pipeline: (1) the magnet table's raw reading, combined with the known
-- roll/pitch tilt, pins down heading exactly -- no ambiguity, no search.
-- (2) each anchor's raw reading is converted to a true world bearing
-- using that heading. (3) the original simple linear resection (no
-- tilt, no heading unknown) resects x, z from those three world
-- bearings. This avoids the iterative/ambiguous solve entirely now that
-- heading is known.

local function dot(p, q) return p[1]*q[1] + p[2]*q[2] + p[3]*q[3] end
local function cross(a, b)
    return { a[2]*b[3]-a[3]*b[2], a[3]*b[1]-a[1]*b[3], a[1]*b[2]-a[2]*b[1] }
end

local function rotateAboutAxis(v, axis, angleRad)
    local cosA, sinA = math.cos(angleRad), math.sin(angleRad)
    local d = dot(v, axis)
    local c = cross(axis, v)
    return {
        v[1]*cosA + c[1]*sinA + axis[1]*d*(1-cosA),
        v[2]*cosA + c[2]*sinA + axis[2]*d*(1-cosA),
        v[3]*cosA + c[3]*sinA + axis[3]*d*(1-cosA),
    }
end

-- Rotates vecToRotate by the shortest-path rotation taking fromV to toV.
local function minimalRotation(fromV, toV, vecToRotate)
    local axis = cross(fromV, toV)
    local axisLen = math.sqrt(dot(axis, axis))
    if axisLen < 1e-9 then return vecToRotate end
    axis = { axis[1]/axisLen, axis[2]/axisLen, axis[3]/axisLen }
    local angle = math.acos(math.max(-1, math.min(1, dot(fromV, toV))))
    return rotateAboutAxis(vecToRotate, axis, angle)
end

-- Reconstructs ld (world-down in local coords) from the gimbal's
-- XAngle/ZAngle, inverting XAngle=atan2(ld.z,-ld.y), ZAngle=atan2(ld.x,-ld.y)
-- using |ld|=1 to fix the scale.
local function reconstructLd(XAngleDeg, ZAngleDeg)
    local tX, tZ = math.tan(math.rad(XAngleDeg)), math.tan(math.rad(ZAngleDeg))
    local ldy = -1 / math.sqrt(1 + tX*tX + tZ*tZ)
    return { -ldy*tZ, ldy, -ldy*tX }
end

-- The contraption's local "up" axis in world coordinates, from pure
-- roll+pitch tilt (no heading/twist). Closed form: up_tilted = (ld.x, -ld.y, ld.z).
local function localUpFromSensor(rollDeg, pitchDeg)
    local ld = reconstructLd(-rollDeg, -pitchDeg) -- CC script negates XAngle/ZAngle
    return { ld[1], -ld[2], ld[3] }
end

-- Local forward/right axes in world coordinates, given heading (deck
-- bearing convention: 0 = ship's forward, clockwise) and roll/pitch.
local function buildForwardRight(headingDeg, rollDeg, pitchDeg)
    local upTilted = localUpFromSensor(rollDeg, pitchDeg)
    local forward0 = minimalRotation({0,1,0}, upTilted, {0,0,1})
    local right0   = minimalRotation({0,1,0}, upTilted, {1,0,0})
    local worldY = {0,1,0}
    local Hr = -math.rad(headingDeg) -- verified sign against real game data
    return rotateAboutAxis(forward0, worldY, Hr), rotateAboutAxis(right0, worldY, Hr)
end

-- Solves for the raft's heading exactly, given the magnetized
-- navtable's raw reading (which always targets true north) and the
-- current roll/pitch. No search loop is strictly required (heading
-- enters as a single rotation), but a 1D scan+refine is used here for
-- robustness and simplicity over deriving a closed form.
local function headingFromMagnet(magnetRawBearing, rollDeg, pitchDeg)
    local worldNorth = { 0, 0, -1 } -- bearing 0 = +z = south, so north = -z
    local function predicted(H)
        local forward, right = buildForwardRight(H, rollDeg, pitchDeg)
        return math.deg(math.atan(dot(worldNorth, forward), dot(worldNorth, right))) % 360
    end
    local function err(H)
        local d = (predicted(H) - magnetRawBearing + 180) % 360 - 180
        return d * d
    end
    local bestH, bestErr = 0, math.huge
    for H = 0, 358, 1 do
        local e = err(H)
        if e < bestErr then bestErr = e; bestH = H end
    end
    local step = 1
    for _ = 1, 100 do
        local improved = false
        for _, d in ipairs({ step, -step }) do
            local e = err(bestH + d)
            if e < bestErr then bestErr = e; bestH = bestH + d; improved = true end
        end
        if not improved then step = step * 0.5 end
        if step < 1e-8 then break end
    end
    return bestH % 360
end

-- Converts one anchor's raw (tilt-corrupted) bearing reading into a
-- true world bearing, given the now-known heading and roll/pitch.
local function rawToWorldBearing(rawDeg, headingDeg, rollDeg, pitchDeg)
    local forward, right = buildForwardRight(headingDeg, rollDeg, pitchDeg)
    local b = math.rad(rawDeg)
    local sinb, cosb = math.sin(b), math.cos(b)
    -- raw = atan2(dot(los,forward), dot(los,right)), los=(sin(world),0,cos(world))
    -- => dot(los,forward) = sinb (up to scale), dot(los,right) = cosb (up to scale)
    local a11, a12 = forward[1], forward[3]
    local a21, a22 = right[1], right[3]
    local det = a11*a22 - a12*a21
    local Sw = (a22*sinb - a12*cosb) / det
    local Cw = (-a21*sinb + a11*cosb) / det
    return math.deg(math.atan(Sw, Cw)) % 360
end

-- Simple closed-form linear resection from three TRUE world bearings
-- (no tilt, no heading unknown -- this is the original method from the
-- very first message, used once tilt/heading have already been
-- corrected for).
local function resect(anchors)
    local sumAA, sumAB, sumBB, sumAC, sumBC = 0, 0, 0, 0, 0
    for _, a in ipairs(anchors) do
        local rad = math.rad(a.bearing)
        local cosB, sinB = math.cos(rad), math.sin(rad)
        local A, B, C = cosB, -sinB, cosB * a.x - sinB * a.z
        sumAA = sumAA + A*A; sumAB = sumAB + A*B; sumBB = sumBB + B*B
        sumAC = sumAC + A*C; sumBC = sumBC + B*C
    end
    local det = sumAA*sumBB - sumAB*sumAB
    if math.abs(det) < 1e-9 then return nil end
    local x = (sumBB*sumAC - sumAB*sumBC) / det
    local z = (sumAA*sumBC - sumAB*sumAC) / det
    return x, z
end

-- Full resection: anchors with RAW bearing readings, the magnetized
-- navtable's RAW reading (always targeting true north), and the
-- current roll/pitch. Returns x, z, heading -- no approximate position
-- needed, since heading is now solved exactly rather than searched for.
--
-- anchors    : { {x=,z=,bearing=<raw>}, ... } (3 anchors)
-- magnetRaw  : the magnetized navtable's raw getRelativeAngle() reading
-- roll, pitch: current gimbal sensor readings (degrees), as read from
--              `roll = -angles[1]; pitch = -angles[2]`
local function resect3(anchors, magnetRaw, roll, pitch)
    local heading = headingFromMagnet(magnetRaw, roll, pitch)

    local worldAnchors = {}
    for i, a in ipairs(anchors) do
        worldAnchors[i] = {
            x = a.x, z = a.z,
            bearing = rawToWorldBearing(a.bearing, heading, roll, pitch),
        }
    end

    local x, z = resect(worldAnchors)
    return x, z, heading
end

return { resect3 = resect3 }