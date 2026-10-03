-- Magnet-referenced resection with full pitch/roll/height correction.
-- Heading comes exactly from a north-pointing (magnetized) navtable; each
-- anchor's raw bearing is converted to a true world bearing (now corrected for
-- the line-of-sight ELEVATION, i.e. height difference), then a linear resection
-- fixes x,z. Elevation couples to position, so a short fixed-point loop refines
-- it -- typically 2-3 passes.
--
-- Because heading is KNOWN (not solved for), this intersects bearing LINES, not
-- circles: no heading ambiguity, no iterative 3-unknown solve, and no danger
-- circle. Two anchors suffice; three or more add a consistency residual.
--
--   x, z, heading, info = resect3(anchors, magnetRaw, roll, pitch, raftY)
--
--   anchors  : { { x=, z=, y=, bearing=<raw getRelativeAngle()> }, ... }  (>=2)
--              y is the anchor's world altitude; needed for the height fix.
--   magnetRaw: raw reading of the north-pointing navtable
--   roll,pitch: gimbal degrees (roll = -XAngle, pitch = -ZAngle as in your CC)
--   raftY    : the craft's world altitude (Minecraft Y)
--
--   info = { ok, reason, iterations, converged,
--            headingResidualDeg,        -- magnet fit quality
--            residualRmsDeg,            -- overall fit error (see note)
--            residualsDeg[], worstAnchor{index,deg},
--            conditioning,              -- ~1 level, ->0 near vertical tilt
--            wellConditioned }          -- false when tilt is too steep to trust
--
-- HEALTH NOTE: residualRmsDeg reliably DETECTS a bad reading (it jumps well
-- above the noise floor). With exactly 3 anchors it cannot reliably say WHICH
-- anchor is bad -- a single error smears across the one redundant equation.
-- A 4th anchor makes worstAnchor trustworthy for isolating the culprit.

local function dot(p, q) return p[1] * q[1] + p[2] * q[2] + p[3] * q[3] end
local function cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function rotateAboutAxis(v, axis, angleRad)
    local cosA, sinA = math.cos(angleRad), math.sin(angleRad)
    local d = dot(v, axis); local c = cross(axis, v)
    return {
        v[1] * cosA + c[1] * sinA + axis[1] * d * (1 - cosA),
        v[2] * cosA + c[2] * sinA + axis[2] * d * (1 - cosA),
        v[3] * cosA + c[3] * sinA + axis[3] * d * (1 - cosA),
    }
end
local function minimalRotation(fromV, toV, vecToRotate)
    local axis = cross(fromV, toV)
    local axisLen = math.sqrt(dot(axis, axis))
    if axisLen < 1e-9 then
        if dot(fromV, toV) < 0 then return { -vecToRotate[1], -vecToRotate[2], -vecToRotate[3] } end
        return vecToRotate
    end
    axis = { axis[1] / axisLen, axis[2] / axisLen, axis[3] / axisLen }
    local angle = math.acos(math.max(-1, math.min(1, dot(fromV, toV))))
    return rotateAboutAxis(vecToRotate, axis, angle)
end
local function reconstructLd(XAngleDeg, ZAngleDeg)
    local tX, tZ = math.tan(math.rad(XAngleDeg)), math.tan(math.rad(ZAngleDeg))
    local ldy = -1 / math.sqrt(1 + tX * tX + tZ * tZ)
    return { -ldy * tZ, ldy, -ldy * tX }
end
local function localUpFromSensor(rollDeg, pitchDeg)
    local ld = reconstructLd(-rollDeg, -pitchDeg)
    return { ld[1], -ld[2], ld[3] }
end
local function buildForwardRight(headingDeg, rollDeg, pitchDeg)
    local upTilted = localUpFromSensor(rollDeg, pitchDeg)
    local forward0 = minimalRotation({ 0, 1, 0 }, upTilted, { 0, 0, 1 })
    local right0   = minimalRotation({ 0, 1, 0 }, upTilted, { 1, 0, 0 })
    local Hr       = -math.rad(headingDeg)
    return rotateAboutAxis(forward0, { 0, 1, 0 }, Hr), rotateAboutAxis(right0, { 0, 1, 0 }, Hr)
end

-- forward model: predict an anchor's RAW reading from a candidate position.
-- Used for the elevation, the residual health-check, and (in tests) to generate
-- synthetic readings.
local function predictRaw(x, z, raftY, ax, ay, az, forward, right)
    local dx, dy, dz = ax - x, ay - raftY, az - z
    local n = math.sqrt(dx * dx + dy * dy + dz * dz)
    if n < 1e-9 then return nil end
    local lx, ly, lz = dx / n, dy / n, dz / n
    local P = lx * forward[1] + ly * forward[2] + lz * forward[3]
    local Q = lx * right[1] + ly * right[2] + lz * right[3]
    return math.deg(math.atan(P, Q)) % 360
end

local function headingFromMagnet(magnetRawBearing, rollDeg, pitchDeg)
    local worldNorth = { 0, 0, -1 }
    local function predicted(H)
        local forward, right = buildForwardRight(H, rollDeg, pitchDeg)
        return math.deg(math.atan(dot(worldNorth, forward), dot(worldNorth, right))) % 360
    end
    local function err(H)
        local d = (predicted(H) - magnetRawBearing + 180) % 360 - 180
        return d * d
    end
    local bestH, bestErr = 0, math.huge
    for H = 0, 359, 1 do
        local e = err(H); if e < bestErr then
            bestErr = e; bestH = H
        end
    end
    local step = 1
    for _ = 1, 200 do
        local improved = false
        for _, d in ipairs({ step, -step }) do
            local e = err(bestH + d)
            if e < bestErr then
                bestErr = e; bestH = bestH + d; improved = true
            end
        end
        if not improved then step = step * 0.5 end
        if step < 1e-9 then break end
    end
    return bestH % 360, math.sqrt(bestErr)
end

-- raw -> true world horizontal bearing, given heading, tilt, AND elevation.
-- elevDeg = angle of the line of sight above horizontal (anchor above => +).
local function rawToWorldBearing(rawDeg, forward, right, elevDeg)
    local E        = math.rad(elevDeg or 0)
    local cr, sr   = math.cos(math.rad(rawDeg)), math.sin(math.rad(rawDeg))
    local f1, f2, f3 = forward[1], forward[2], forward[3]
    local r1, r2, r3 = right[1], right[2], right[3]
    local alpha    = f1 * cr - r1 * sr
    local beta     = f3 * cr - r3 * sr
    local gamma    = -math.tan(E) * (f2 * cr - r2 * sr)
    local M        = math.sqrt(alpha * alpha + beta * beta)
    if M < 1e-12 then return nil end -- tilt singularity
    local ratio = gamma / M
    if ratio > 1 then ratio = 1 elseif ratio < -1 then ratio = -1 end
    local delta = math.atan(beta, alpha)
    local asinV = math.asin(ratio)
    local cE = math.cos(E)
    local best, bestErr
    for _, W in ipairs({ asinV - delta, (math.pi - asinV) - delta }) do
        local lx, ly, lz = math.sin(W) * cE, math.sin(E), math.cos(W) * cE
        local P = lx * f1 + ly * f2 + lz * f3
        local Q = lx * r1 + ly * r2 + lz * r3
        local pred = math.deg(math.atan(P, Q))
        local d = math.abs(((pred - rawDeg + 180) % 360) - 180)
        if not bestErr or d < bestErr then
            bestErr = d; best = W
        end
    end
    return math.deg(best) % 360
end

local function resect(anchors)
    local sumAA, sumAB, sumBB, sumAC, sumBC = 0, 0, 0, 0, 0
    for _, a in ipairs(anchors) do
        local rad = math.rad(a.bearing)
        local cosB, sinB = math.cos(rad), math.sin(rad)
        local A, B, C = cosB, -sinB, cosB * a.x - sinB * a.z
        sumAA = sumAA + A * A; sumAB = sumAB + A * B; sumBB = sumBB + B * B
        sumAC = sumAC + A * C; sumBC = sumBC + B * C
    end
    local det = sumAA * sumBB - sumAB * sumAB
    if math.abs(det) < 1e-9 then return nil end
    local x = (sumBB * sumAC - sumAB * sumBC) / det
    local z = (sumAA * sumBC - sumAB * sumAC) / det
    return x, z, det
end

-- anchors: { {x=,z=,y=,bearing=<raw>}, ... }  (>=2; 3+ gives a residual check)
-- magnetRaw: north-pointing navtable raw reading
-- roll,pitch: gimbal sensor degrees;  raftY: craft altitude (world Y)
-- returns x, z, heading, info
local function resect3(anchors, magnetRaw, roll, pitch, raftY)
    raftY = raftY or 0
    local n = #anchors
    if n < 2 then return nil, nil, nil, { ok = false, reason = "need at least 2 anchors" } end

    local heading, magResid = headingFromMagnet(magnetRaw, roll, pitch)
    local forward, right = buildForwardRight(heading, roll, pitch)
    -- horizontal-projection conditioning: ~1 when level, ->0 as tilt nears
    -- vertical (heading-invariant). Below ~0.12 the geometry is too flat to invert
    -- a horizontal bearing reliably, so the answer can't be trusted.
    local detFR = math.abs(forward[1] * right[3] - forward[3] * right[1])
    if detFR < 0.12 then
        return nil, nil, heading,
            { ok = false, reason = "tilt too close to vertical (degenerate)", conditioning = detFR }
    end

    local elev = {}; for i = 1, n do elev[i] = 0 end
    local x, z, lastDet, converged, iters = nil, nil, nil, false, 0
    for it = 1, 12 do
        iters = it
        local wa = {}
        for i, a in ipairs(anchors) do
            local wb = rawToWorldBearing(a.bearing, forward, right, elev[i])
            if not wb then return nil, nil, heading, { ok = false, reason = "bearing inversion singular" } end
            wa[i] = { x = a.x, z = a.z, bearing = wb }
        end
        local nx, nz, det = resect(wa)
        if not nx then return nil, nil, heading, { ok = false, reason = "degenerate anchor geometry" } end
        local dx = x and (nx - x) or 1e9
        local dz = z and (nz - z) or 1e9
        x, z, lastDet = nx, nz, det
        for i, a in ipairs(anchors) do
            local horiz = math.sqrt((a.x - x) ^ 2 + (a.z - z) ^ 2)
            elev[i] = math.deg(math.atan((a.y or 0) - raftY, math.max(horiz, 1e-6)))
        end
        if it > 1 and math.abs(dx) < 1e-5 and math.abs(dz) < 1e-5 then
            converged = true; break
        end
    end

    -- residual health-check (meaningful only when overdetermined, n >= 3)
    local sse, worstIdx, worstAbs = 0, 0, -1
    local perAnchorDeg = {}
    for i, a in ipairs(anchors) do
        local pr = predictRaw(x, z, raftY, a.x, a.y or 0, a.z, forward, right)
        local d = ((pr - a.bearing + 180) % 360) - 180
        perAnchorDeg[i] = d; sse = sse + d * d
        if math.abs(d) > worstAbs then
            worstAbs = math.abs(d); worstIdx = i
        end
    end
    return x, z, heading, {
        ok = true,
        iterations = iters,
        converged = converged,
        headingResidualDeg = magResid,
        residualRmsDeg = math.sqrt(sse / n),
        residualsDeg = perAnchorDeg,
        worstAnchor = { index = worstIdx, deg = perAnchorDeg[worstIdx] },
        conditioning = detFR,
        wellConditioned = (detFR > 0.30) and (math.abs(lastDet) > 1e-6),
    }
end

return { resect3 = resect3, _predictRaw = predictRaw, _buildForwardRight = buildForwardRight }
