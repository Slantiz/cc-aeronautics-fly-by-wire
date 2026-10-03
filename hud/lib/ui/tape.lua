local Element = require("lib.ui.element")
local util    = require("lib.ui.util")

---@class Tape : Element
---@field params table
---@field field string
---@field increment number
local Tape = setmetatable({}, Element)
Tape.__index = Tape

local CHARS_PER_NOTCH = 2  -- one blank char between consecutive notches
local WIDTH           = 3  -- character columns

---@param x number
---@param y number
---@param h number
---@param params table
---@param field string      field name in params to read (e.g. "velocity")
---@param increment number  value difference between consecutive notches
---@return Tape
function Tape:new(x, y, h, params, field, increment)
    local obj     = Element.new(self, x, y, WIDTH, h) --[[@as Tape]]
    obj.params    = params
    obj.field     = field
    obj.increment = increment
    return obj
end

---@param screen Screen
---@param absX number
---@param absY number
function Tape:draw(screen, absX, absY)
    local target   = screen.target
    local h        = self.h
    local v        = self.params[self.field] or 0
    local inc      = self.increment
    local upc      = inc / CHARS_PER_NOTCH       -- value per char row
    local center_r = math.ceil(h / 2)

    for r = 1, h do
        local y = absY + r - 1
        -- per-column char / fg / bg; defaults clear the row to gray
        local text  = "   "
        local mask  = "BBB"
        local bg1   = colors.gray   -- leftmost cell carries the highlight

        if r == center_r then
            -- fixed current readout: orange highlight, decimals shown dim
            text, mask = util.formatCompact(v, WIDTH, true)
            bg1 = colors.orange
        else
            local v_row   = v + (center_r - r) * upc
            local nearest = math.floor(v_row / inc + 0.5) * inc
            local frow    = center_r - (nearest - v) * CHARS_PER_NOTCH / inc
            if math.floor(frow + 0.5) == r then
                -- notch: integer reading, left-aligned to line up with the readout;
                -- red highlight for negatives avoids needing a minus sign
                text, mask = util.formatCompact(nearest, WIDTH, false)
                bg1 = nearest < 0 and colors.red or colors.green
            end
        end

        for i = 1, WIDTH do
            target.setCursorPos(absX + i - 1, y)
            target.setBackgroundColor(i == 1 and bg1 or colors.gray)
            target.setTextColor(mask:sub(i, i) == "D" and colors.lightGray or colors.white)
            target.write(text:sub(i, i))
        end
    end
end

return Tape
