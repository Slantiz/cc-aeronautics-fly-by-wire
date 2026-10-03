local Element    = require("lib.ui.element")
local Canvas     = require("lib.ui.canvas")

---@class Scale : Element
---@field canvas Canvas
---@field params table
---@field field string
---@field notches { [1]: number, [2]: number }[]
---@field unitsPerBixel number
local Scale      = setmetatable({}, Element)
Scale.__index    = Scale

-- A horizontal scale: fixed notch marks at given values, plus a pointer that
-- slides to the current value. One character tall; drawn at bixel resolution.
-- Everything is white.
--
-- Notches grow upward from the bottom row by their height (in bixels). The
-- pointer is a downward arrow: a tip on the middle row with two wings one bixel
-- out on the top row.
---@param x number
---@param y number
---@param w number             width in characters (height is fixed at 1)
---@param params table
---@param field string         field in params holding the current value
---@param notches { [1]: number, [2]: number }[]  list of {value, height-in-bixels}
---@param unitsPerBixel number value-units spanned by one bixel column
---@return Scale
function Scale:new(x, y, w, params, field, notches, unitsPerBixel)
    local obj         = Element.new(self, x, y, w, 1) --[[@as Scale]]
    obj.canvas        = Canvas:new(1, 1, w, 1, colors.gray)
    obj.params        = params
    obj.field         = field
    obj.notches       = notches
    obj.unitsPerBixel = unitsPerBixel
    return obj
end

---@param screen Screen
---@param absX number
---@param absY number
function Scale:draw(screen, absX, absY)
    local canvas = self.canvas
    local bw     = canvas.w * 2
    -- integer centre column (char to the right of the true midpoint for even
    -- widths) so the offset below rounds to the nearest pixel rather than
    -- truncating toward it
    local center = math.floor(bw / 2) + 1
    local value  = self.params[self.field] or 0
    local upb    = self.unitsPerBixel

    canvas:clear(colors.gray)

    local function colOf(v)
        return center + math.floor(v / upb + 0.5)
    end
    local function plot(col, row, color, prio)
        if col >= 1 and col <= bw then
            canvas:setPixel(col, row, color, prio)
        end
    end

    local tip = colOf(value)

    -- fixed white notches, each growing upward from the bottom row.
    -- everything is white at priority 0, so overlapping notch/arrow pixels in
    -- one character cell all render together (no pixel is hidden).
    for _, n in ipairs(self.notches) do
        local col, height = colOf(n[1]), n[2]
        -- if a wing sits directly above a 2-tall notch the column reads as a
        -- bar, not an arrow; shorten that notch to 1 bixel so the wing stands out
        if height > 1 and (col == tip - 1 or col == tip + 1) then
            height = 1
        end
        for k = 0, height - 1 do
            plot(col, 3 - k, colors.white, 0)
        end
    end

    -- pointer: tip on the middle row, wings one bixel out on the top row
    plot(tip, 2, colors.white, 0)
    plot(tip - 1, 1, colors.white, 0)
    plot(tip + 1, 1, colors.white, 0)

    canvas:draw(screen, absX, absY)
end

return Scale
