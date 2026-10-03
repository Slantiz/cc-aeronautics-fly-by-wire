local Element     = require("lib.ui.element")
local Canvas      = require("lib.ui.canvas")
local Button      = require("lib.ui.button")
local Toggle      = require("lib.ui.toggle")
local Label       = require("lib.ui.label")

---@class RouteSegment
---@field straight? number  distance in metres on the current bearing
---@field turn? number      turn in degrees (+ = right) for this arc
---@field radius? number    arc radius in metres (required with turn)

---@class Route
---@field heading number              initial bearing from north, degrees
---@field segments RouteSegment[]

---@class Nd : Element
---@field canvas Canvas
---@field params { turnRadius: number, heading: number, route: Route, runways: table[] }
---@field zoomIndex number
---@field zoomIn Button
---@field zoomOut Button
---@field trackToggle Toggle
---@field predToggle Toggle
---@field rangeLabel Label
local Nd          = setmetatable({}, Element)
Nd.__index        = Nd

local PRIO_RING   = 1 -- range rings (lowest)
local PRIO_RUNWAY = 2 -- runways (above rings, below the tracks)
local PRIO_TREND  = 3 -- predicted flight path (green)
local PRIO_ROUTE  = 4 -- planned route (magenta), wins over the trend
local PRIO_SHIP   = 5 -- ownship arrow
local PRIO_BORDER = 6 -- side frame (always on top)
local RING_COUNT  = 3

-- selectable spacings between adjacent rings, in metres (1-2.5-5 sequence)
local RANGES      = { 100, 250, 500, 1000, 1500, 2500, 5000, 10000, 25000, 50000, 100000 }

-- human-readable range label: plain below 1000, else K/M with up to one decimal
local function formatRange(m)
    if m < 1000 then
        return tostring(m)
    elseif m < 1000000 then
        local k = m / 1000
        return k == math.floor(k) and string.format("%dK", k) or string.format("%.1fK", k)
    else
        local n = m / 1000000
        return n == math.floor(n) and string.format("%dM", n) or string.format("%.1fM", n)
    end
end

---@param x number
---@param y number
---@param w number
---@param h number
---@param params { turnRadius: number }   signed turn radius in metres (0 = straight)
---@return Nd
function Nd:new(x, y, w, h, params)
    local obj       = Element.new(self, x, y, w, h) --[[@as Nd]]
    obj.canvas      = Canvas:new(1, 1, w, h, colors.black)
    obj.params      = params
    obj.zoomIndex   = 3 -- default: 500 m between rings
    -- bottom-row controls: two zoom buttons and the range readout. These are
    -- owned and positioned (in element-local coords) by the Nd, which draws
    -- them and routes clicks to them itself (see Nd:draw / Nd:handleClick).
    obj.zoomIn      = Button:new(2, h, 3, 1, "+", function()
        obj.zoomIndex = math.max(1, obj.zoomIndex - 1)
    end)
    obj.zoomOut     = Button:new(5, h, 3, 1, "-", function()
        obj.zoomIndex = math.min(#RANGES, obj.zoomIndex + 1)
    end)
    -- track toggles, one row above the zoom buttons (T = route, P = predicted),
    -- each lit in its own track colour when on
    obj.trackToggle = Toggle:new(2, h - 1, 3, 1, "T", colors.magenta)
    obj.predToggle  = Toggle:new(5, h - 1, 3, 1, "P", colors.green)
    obj.rangeLabel  = Label:new(1, h, "", colors.white, colors.black)
    return obj
end

---@param screen Screen
---@param absX number
---@param absY number
function Nd:draw(screen, absX, absY)
    local canvas   = self.canvas
    local bw, bh   = canvas.w * 2, canvas.h * 3
    local ox       = math.floor(bw / 2) + 1            -- bixel right of the true middle
    local oy       = bh - 8                            -- nose; arrow occupies the row 2 chars off the bottom
    local R        = self.params.turnRadius
    local H        = self.params.heading or 0          -- heading-up rotation
    local route    = self.params.route                 -- planned track (world frame)
    local spacing  = math.floor((oy - 2) / RING_COUNT) -- bixels between rings
    local ringDist = RANGES[self.zoomIndex]            -- metres between rings
    local mpb      = ringDist / spacing                -- metres per bixel

    canvas:clear(colors.black)

    local function plot(bx, by, color, prio)
        bx, by = math.floor(bx + 0.5), math.floor(by + 0.5)
        if bx >= 1 and bx <= bw and by >= 1 and by <= bh then
            canvas:setPixel(bx, by, color, prio)
        end
    end

    -- Borders sit on the right bixel of the first and last chars (bixel 2 and
    -- bixel bw). That leaves an odd number of bixels between them, so the true
    -- centre is a single bixel (ox). Content must stay clear of the bixels
    -- adjacent to each border, hence the inner [xMin, xMax] window.
    local xMin, xMax = 4, bw - 2

    -- Liang-Barsky clip of a segment to the inner window [xMin,xMax]x[1,bh]
    local function clipLine(x1, y1, x2, y2)
        local dx, dy = x2 - x1, y2 - y1
        local t0, t1 = 0, 1
        local edges = { { -dx, x1 - xMin }, { dx, xMax - x1 }, { -dy, y1 - 1 }, { dy, bh - y1 } }
        for _, e in ipairs(edges) do
            local p, q = e[1], e[2]
            if p == 0 then
                if q < 0 then return nil end
            else
                local r = q / p
                if p < 0 then
                    if r > t1 then return nil elseif r > t0 then t0 = r end
                else
                    if r < t0 then return nil elseif r < t1 then t1 = r end
                end
            end
        end
        return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
    end

    -- draw a polyline with the same primitive as the pitch ladder: one clean
    -- Bresenham canvas:line per segment (clipped to the inner window)
    local function drawPath(points, color, prio)
        for i = 2, #points do
            local a, b = points[i - 1], points[i]
            local cx1, cy1, cx2, cy2 = clipLine(a[1], a[2], b[1], b[2])
            if cx1 then
                canvas:line(math.floor(cx1 + 0.5), math.floor(cy1 + 0.5),
                    math.floor(cx2 + 0.5), math.floor(cy2 + 0.5), color, prio)
            end
        end
    end

    -- world point (east/north metres from the ownship) -> float bixel, rotated
    -- so the current heading points up (heading-up) and scaled by the zoom
    local sinH, cosH = math.sin(math.rad(H)), math.cos(math.rad(H))
    local function worldToBixel(east, north)
        local fwd = east * sinH + north * cosH
        local rgt = east * cosH - north * sinH
        return ox + rgt / mpb, oy - fwd / mpb
    end

    -- range rings: equally spaced upper semicircles centred on the ownship,
    -- drawn with the midpoint-circle algorithm so they stay exactly 1 px thick
    local function ringPlot(bx, by)
        if bx >= xMin and bx <= xMax then plot(bx, by, colors.gray, PRIO_RING) end
    end
    for i = 1, RING_COUNT do
        local r = i * spacing
        local x, y, err = r, 0, 1 - r
        while x >= y do
            ringPlot(ox + x, oy - y)
            ringPlot(ox - x, oy - y)
            ringPlot(ox + y, oy - x)
            ringPlot(ox - y, oy - x)
            y = y + 1
            if err < 0 then
                err = err + 2 * y + 1
            else
                x = x - 1
                err = err + 2 * (y - x) + 1
            end
        end
    end

    local maxPts = 4 * (bw + bh) -- safety cap on points per path

    -- runways (white): a line between two world points (east/north metres from
    -- the ownship). Above the rings, below the tracks (see cleanup + priorities).
    for _, rw in ipairs(self.params.runways or {}) do
        local a, b = rw[1], rw[2]
        drawPath({ { worldToBixel(a[1], a[2]) }, { worldToBixel(b[1], b[2]) } },
            colors.white, PRIO_RUNWAY)
    end

    -- predicted flight path (green): tangent to "up" at the nose (aircraft
    -- frame). A straight is one canvas:line; an arc is a few Bresenham chords.
    if self.predToggle.on then
        local ar = R and math.abs(R) or 0
        local pts
        if ar == 0 then
            pts = { { ox, oy }, { ox, oy - bh } } -- straight up, clipped to the top
        else
            pts = { { ox, oy } }
            local dphi = math.min(math.pi / 2, 4 * mpb / ar) -- ~4 px chords
            local phi = 0
            for _ = 1, maxPts do
                phi = math.min(phi + dphi, math.pi)
                local bx = ox + R * (1 - math.cos(phi)) / mpb
                local by = oy - ar * math.sin(phi) / mpb
                pts[#pts + 1] = { bx, by }
                if phi >= math.pi or bx < xMin or bx > xMax or by < 1 then break end
            end
        end
        drawPath(pts, colors.lime, PRIO_TREND)
    end

    -- planned route (magenta): straights and turns defined relative to north,
    -- anchored at the ownship and rotated into the heading-up display
    if route and self.trackToggle.on then
        local pts         = { { worldToBixel(0, 0) } }
        local wx, wy, hdg = 0, 0, route.heading or 0
        for _, seg in ipairs(route.segments or {}) do
            if #pts >= maxPts then break end
            if seg.straight then
                -- one point for the whole leg -> a single clean canvas:line
                wx = wx + seg.straight * math.sin(math.rad(hdg))
                wy = wy + seg.straight * math.cos(math.rad(hdg))
                pts[#pts + 1] = { worldToBixel(wx, wy) }
            elseif seg.turn and seg.radius then
                local dphi  = math.min(math.pi / 2, 4 * mpb / math.abs(seg.radius)) -- ~4 px chords
                local steps = math.max(1, math.ceil(math.abs(math.rad(seg.turn)) / dphi))
                local dDeg  = seg.turn / steps
                local dLen  = math.abs(math.rad(dDeg)) * seg.radius
                for _ = 1, steps do
                    if #pts >= maxPts then break end
                    hdg = hdg + dDeg
                    wx = wx + dLen * math.sin(math.rad(hdg))
                    wy = wy + dLen * math.cos(math.rad(hdg))
                    pts[#pts + 1] = { worldToBixel(wx, wy) }
                end
            end
        end
        drawPath(pts, colors.magenta, PRIO_ROUTE)
    end

    -- isolate each path cell to a single colour on black, in priority order:
    -- route (magenta) > trend (green) > runway (white) > ring (gray). So we
    -- never get a muddy multi-colour cell, and lower layers yield to higher.
    local buf, pri = canvas.buffer, canvas.priority
    for cy = 0, canvas.h - 1 do
        for cx = 0, canvas.w - 1 do
            local bx0, by0 = cx * 2 + 1, cy * 3 + 1
            local hasM, hasL, hasW = false, false, false
            for dy = 0, 2 do
                for dx = 0, 1 do
                    local c = buf[by0 + dy][bx0 + dx]
                    if c == colors.magenta then hasM = true
                    elseif c == colors.lime then hasL = true
                    elseif c == colors.white then hasW = true end
                end
            end
            local keep = hasM and colors.magenta or hasL and colors.lime or hasW and colors.white or nil
            if keep then
                for dy = 0, 2 do
                    for dx = 0, 1 do
                        if buf[by0 + dy][bx0 + dx] ~= keep then
                            buf[by0 + dy][bx0 + dx] = colors.black
                            pri[by0 + dy][bx0 + dx] = 0
                        end
                    end
                end
            end
        end
    end

    -- ownship: small filled white arrowhead, apex at (ox, oy)
    --   . W .
    --   W W W
    plot(ox, oy, colors.white, PRIO_SHIP)
    plot(ox - 1, oy + 1, colors.white, PRIO_SHIP)
    plot(ox, oy + 1, colors.white, PRIO_SHIP)
    plot(ox + 1, oy + 1, colors.white, PRIO_SHIP)

    -- side borders (left/right only), both on the *right* bixel of their char
    -- (bixel 2 and bixel bw) so the gap between them is an odd number of bixels
    for by = 1, bh do
        plot(2, by, colors.white, PRIO_BORDER)
        plot(bw, by, colors.white, PRIO_BORDER)
    end

    canvas:draw(screen, absX, absY)

    -- bottom-row controls: toggles, zoom buttons and the ring-spacing readout
    local function drawChild(c)
        c:draw(screen, absX + c.x - 1, absY + c.y - 1)
    end
    drawChild(self.trackToggle)
    drawChild(self.predToggle)
    drawChild(self.zoomIn)
    drawChild(self.zoomOut)
    self.rangeLabel.text = formatRange(ringDist)
    -- right-aligned just inside the right border
    self.rangeLabel:draw(screen, absX + self.w - 1 - #self.rangeLabel.text, absY + self.h - 1)
end

---@param clickX number
---@param clickY number
---@param absX number
---@param absY number
---@return boolean
function Nd:handleClick(clickX, clickY, absX, absY)
    for _, btn in ipairs({ self.zoomIn, self.zoomOut, self.trackToggle, self.predToggle }) do
        local bx, by = absX + btn.x - 1, absY + btn.y - 1
        if clickX >= bx and clickX <= bx + btn.w - 1
            and clickY >= by and clickY <= by + btn.h - 1 then
            return btn:handleClick(clickX, clickY, bx, by)
        end
    end
    return false
end

return Nd
