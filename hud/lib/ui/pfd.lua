local Element     = require("lib.ui.element")
local Canvas      = require("lib.ui.canvas")
local util        = require("lib.ui.util")
local Tape        = require("lib.ui.tape")
local Scale       = require("lib.ui.scale")
local Compass     = require("lib.ui.compass")

---@class PFD : Element
---@field horizonCanvas Canvas
---@field velTape Tape
---@field altTape Tape
---@field rollScale Scale
---@field headingCompass Compass
---@field params { pitch: number, roll: number, heading: number, velocity: number, altitude: number }
---@field debug boolean
---@field debugPriority boolean
local PFD         = setmetatable({}, Element)
PFD.__index       = PFD

local PRIO_BAR    = 1
local PRIO_SYMBOL = 2
local PRIO_MASK   = 3
local MASK_MARGIN = 0 -- no side margin; corners only
local MASK_CR     = 4 -- corner radius in bixels
local TAPE_W      = 3 -- chars per side tape

local function drawHorizon(canvas, cx, cy, pitch, roll, debug)
    local bw          = canvas.w * 2
    local bh          = canvas.h * 3
    local cosR        = math.cos(math.rad(roll))
    -- negated so positive roll banks clockwise (right wing down), matching
    -- the bank indicator; the pitch bars use the same sign to stay aligned
    local sinR        = -math.sin(math.rad(roll))
    local pitchOffset = pitch * bh / 60
    local hcx         = cx + pitchOffset * sinR
    local hcy         = cy - pitchOffset * cosR
    local buf         = canvas.buffer
    local pri         = canvas.priority
    for by = 1, bh do
        local brow, prow = buf[by], pri[by]
        local cellY = math.floor((by - 1) / 3)
        for bx = 1, bw do
            local dot = (bx - hcx) * sinR - (by - hcy) * cosR
            local sky = dot > 0
            local color
            if debug then
                local odd = ((math.floor((bx - 1) / 2) + cellY) % 2) == 1
                color = sky and (odd and colors.blue or colors.lightBlue)
                    or (odd and colors.orange or colors.brown)
            else
                color = sky and colors.lightBlue or colors.brown
            end
            brow[bx] = color
            prow[bx] = 0
        end
    end
end

local function drawPitchBars(canvas, cx, cy, pitch, roll)
    local bw    = canvas.w * 2
    local bh    = canvas.h * 3
    local cosR  = math.cos(math.rad(roll))
    local sinR  = -math.sin(math.rad(roll)) -- see drawHorizon: positive roll = clockwise
    local halfW = math.floor(bw * 0.2)
    for deg = -30, 30, 10 do
        if deg ~= 0 then
            local wy     = (deg - pitch) * bh / 60
            local x1, y1 = util.rotateAround(cx - halfW - 1, cy + wy, cx, cy, cosR, sinR)
            local x2, y2 = util.rotateAround(cx + halfW, cy + wy, cx, cy, cosR, sinR)
            canvas:line(
                math.floor(x1 + 0.5), math.floor(y1 + 0.5),
                math.floor(x2 + 0.5), math.floor(y2 + 0.5),
                colors.white, PRIO_BAR)
        end
    end
end

-- Standard 4-corner rounded rect mask. Only the horizon canvas is masked;
-- the label rows are separate text drawn outside the canvas entirely.
local function applyMask(canvas)
    local bw  = canvas.w * 2
    local bh  = canvas.h * 3
    local m   = MASK_MARGIN
    local cr  = MASK_CR
    local buf = canvas.buffer
    local pri = canvas.priority
    for by = 1, bh do
        local brow, prow = buf[by], pri[by]
        local y          = by - 1
        local yr         = bh - by
        for bx = 1, bw do
            local x       = bx - 1
            local xr      = bw - bx
            local outside = x < m or xr < m
            if not outside then
                if y < cr then
                    if x < m + cr then
                        local dx, dy = x - (m + cr), y - cr
                        if dx * dx + dy * dy > cr * cr then outside = true end
                    elseif xr < m + cr then
                        local dx, dy = xr - (m + cr), y - cr
                        if dx * dx + dy * dy > cr * cr then outside = true end
                    end
                elseif yr < cr then
                    if x < m + cr then
                        local dx, dy = x - (m + cr), yr - cr
                        if dx * dx + dy * dy > cr * cr then outside = true end
                    elseif xr < m + cr then
                        local dx, dy = xr - (m + cr), yr - cr
                        if dx * dx + dy * dy > cr * cr then outside = true end
                    end
                end
            end
            if outside then
                brow[bx] = colors.black
                prow[bx] = PRIO_MASK
            end
        end
    end
end

local function drawSymbol(canvas, lcx, lcy, armLen, gap)
    local ay  = lcy
    local lx1 = lcx - gap - armLen
    local lx2 = lcx - gap - 1
    local rx1 = lcx + 2 + gap
    local rx2 = lcx + 1 + gap + armLen
    canvas:line(lx1, ay, lx2, ay, colors.black, PRIO_SYMBOL)
    canvas:line(rx1, ay, rx2, ay, colors.black, PRIO_SYMBOL)
    canvas:line(lx2, ay, lx2, ay + 2, colors.black, PRIO_SYMBOL)
    canvas:line(rx1, ay, rx1, ay + 2, colors.black, PRIO_SYMBOL)
    canvas:setPixel(lcx, lcy, colors.black, PRIO_SYMBOL)
    canvas:setPixel(lcx + 1, lcy, colors.black, PRIO_SYMBOL)
    canvas:setPixel(lcx, lcy + 1, colors.black, PRIO_SYMBOL)
    canvas:setPixel(lcx + 1, lcy + 1, colors.black, PRIO_SYMBOL)
end

---@param x number
---@param y number
---@param w number  total width including both tapes (must be >= 2*TAPE_W + 1)
---@param h number
---@param params { pitch: number, roll: number, heading: number, velocity: number, altitude: number }
---@return PFD
function PFD:new(x, y, w, h, params)
    local obj          = Element.new(self, x, y, w, h) --[[@as PFD]]
    -- 1-char gap between each tape and the horizon view
    local horizW       = w - 2 * TAPE_W - 2
    -- h-2: top and bottom rows are label rows drawn outside the canvas
    obj.horizonCanvas  = Canvas:new(1, 1, horizW, h - 2, colors.black)
    obj.velTape        = Tape:new(0, 0, h, params, "velocity", 5)
    obj.altTape        = Tape:new(0, 0, h, params, "altitude", 20)
    -- roll scale: 5° per bixel; 0/±20/±45 notches are 2 bixels tall, others 1
    obj.rollScale      = Scale:new(0, 0, horizW, params, "roll", {
        { -45, 2 }, { -30, 1 }, { -20, 2 }, { -10, 1 }, { 0, 2 },
        { 10,  1 }, { 20, 2 }, { 30, 1 }, { 45, 2 },
    }, 5)
    obj.headingCompass = Compass:new(0, 0, horizW, params, "heading")
    obj.params         = params
    return obj
end

---@param screen Screen
---@param absX number
---@param absY number
function PFD:draw(screen, absX, absY)
    local canvas  = self.horizonCanvas
    local horizW  = canvas.w
    local bw      = horizW * 2
    local bh      = canvas.h * 3
    local cx      = (bw + 1) / 2
    local cy      = (bh + 1) / 2 + 1
    local pitch   = self.params.pitch or 0
    local roll    = self.params.roll or 0

    -- side tapes (full height), with a 1-char gap before/after the horizon
    self.velTape:draw(screen, absX, absY)
    self.altTape:draw(screen, absX + TAPE_W + 1 + horizW + 1, absY)

    drawHorizon(canvas, cx, cy, pitch, roll, self.debug)
    if not self.debugPriority then
        drawPitchBars(canvas, cx, cy, pitch, roll)
        drawSymbol(canvas, math.floor(cx), math.floor(cy),
            math.max(4, math.floor(bw / 6)), 4)
    end
    applyMask(canvas)
    -- horizon canvas sits one row below the top label, one char right of the vel tape
    canvas:draw(screen, absX + TAPE_W + 1, absY + 1)

    local labelX = absX + TAPE_W + 1

    -- top: roll scale (notches + pointer); bottom: heading compass
    self.rollScale:draw(screen, labelX, absY)
    self.headingCompass:draw(screen, labelX, absY + self.h - 1)
end

return PFD
