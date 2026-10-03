local Element = require("lib.ui.element")

---@class Compass : Element
---@field params table
---@field field string
local Compass = setmetatable({}, Element)
Compass.__index = Compass

-- Notches sit every 15°, spaced 3 chars apart (the notch char plus two blanks),
-- so a cardinal and its neighbouring diagonal have two plain notches between.
local DEG_PER_CHAR  = 5
local DEG_PER_NOTCH = 15

local CARDINALS = { [0] = "N", [90] = "E", [180] = "S", [270] = "W" }
-- diagonals: { north/south component (coloured), east/west component }
local DIAGONALS = { [45] = { "N", "E" }, [135] = { "S", "E" }, [225] = { "S", "W" }, [315] = { "N", "W" } }

---@param x number
---@param y number
---@param w number       width in characters (height is fixed at 1)
---@param params table
---@param field string   field in params holding the heading in degrees
---@return Compass
function Compass:new(x, y, w, params, field)
    local obj  = Element.new(self, x, y, w, 1) --[[@as Compass]]
    obj.params = params
    obj.field  = field
    return obj
end

---@param screen Screen
---@param absX number
---@param absY number
function Compass:draw(screen, absX, absY)
    local target  = screen.target
    local w       = self.w
    -- middle char: for even widths the centre is a border, so take the char to
    -- the right (matches the tapes' centre convention)
    local center  = math.floor(w / 2) + 1
    local heading = (self.params[self.field] or 0) % 360

    -- write one cell; the centre char is always the orange pointer
    local function cell(pos, bg, fg, ch)
        if pos < 1 or pos > w then return end
        if pos == center then bg = colors.orange end
        target.setCursorPos(absX + pos - 1, absY)
        target.setBackgroundColor(bg)
        target.setTextColor(fg)
        target.write(ch)
    end

    -- clear the strip, then lay down the fixed pointer
    target.setBackgroundColor(colors.gray)
    for i = 1, w do
        target.setCursorPos(absX + i - 1, absY)
        target.write(" ")
    end
    cell(center, colors.orange, colors.white, " ")

    -- place every notch at its scrolled position
    for nv = 0, 360 - DEG_PER_NOTCH, DEG_PER_NOTCH do
        local d = (nv - heading) % 360
        if d > 180 then d = d - 360 end
        local pos = center + math.floor(d / DEG_PER_CHAR + 0.5)
        if CARDINALS[nv] then
            cell(pos, colors.blue, colors.white, CARDINALS[nv])
        elseif DIAGONALS[nv] then
            -- coloured cell on the left, plain second letter to its right
            cell(pos,     colors.lightBlue, colors.white, DIAGONALS[nv][1])
            cell(pos + 1, colors.gray,      colors.white, DIAGONALS[nv][2])
        else
            cell(pos, colors.lightGray, colors.lightGray, " ")
        end
    end
end

return Compass
