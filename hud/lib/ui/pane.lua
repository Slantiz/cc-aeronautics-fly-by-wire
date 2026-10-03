local Element = require("lib.ui.element")

---@class Pane : Element
---@field isVisible boolean
---@field bgColor number
---@field elements Element[]
local Pane = setmetatable({}, Element)
Pane.__index = Pane

---@param x number
---@param y number
---@param w number
---@param h number
---@param bgColor? number
---@return Pane
function Pane:new(x, y, w, h, bgColor)
    local obj = Element.new(self, x, y, w, h) --[[@as Pane]]
    obj.isVisible = true
    obj.bgColor = bgColor or colors.black
    obj.elements = {}
    return obj
end

---@param visible boolean
---@return Pane
function Pane:visible(visible)
    self.isVisible = visible
    return self
end

---@param a Element
---@param b Element
---@return boolean
local function overlaps(a, b)
    return not (
        a.x + a.w - 1 < b.x or b.x + b.w - 1 < a.x or
        a.y + a.h - 1 < b.y or b.y + b.h - 1 < a.y
    )
end

---@param element Element
---@return Pane
function Pane:add(element)
    if not (element.x >= 1 and element.y >= 1 and
            element.x + element.w - 1 <= self.w and
            element.y + element.h - 1 <= self.h) then
        error(("Slate: element at (%d,%d) size %dx%d is out of pane bounds %dx%d")
            :format(element.x, element.y, element.w, element.h, self.w, self.h), 2)
    end
    for _, existing in ipairs(self.elements) do
        if overlaps(element, existing) then
            error(("Slate: element at (%d,%d) size %dx%d overlaps existing element at (%d,%d) size %dx%d")
                :format(element.x, element.y, element.w, element.h, existing.x, existing.y, existing.w, existing.h), 2)
        end
    end
    table.insert(self.elements, element)
    return self
end

---@param screen Screen
---@param absX number
---@param absY number
function Pane:draw(screen, absX, absY)
    local t = screen.target
    local oldBg = t.getBackgroundColor()

    t.setBackgroundColor(self.bgColor)
    for row = 0, self.h - 1 do
        t.setCursorPos(absX, absY + row)
        t.write(string.rep(" ", self.w))
    end

    for _, element in ipairs(self.elements) do
        element:draw(screen, absX + element.x - 1, absY + element.y - 1)
    end

    t.setBackgroundColor(oldBg)
end

---@param clickX number
---@param clickY number
---@param absX number
---@param absY number
---@return boolean
function Pane:handleClick(clickX, clickY, absX, absY)
    for _, element in ipairs(self.elements) do
        local childAbsX = absX + element.x - 1
        local childAbsY = absY + element.y - 1
        if clickX >= childAbsX and clickX <= childAbsX + element.w - 1
        and clickY >= childAbsY and clickY <= childAbsY + element.h - 1 then
            if element:handleClick(clickX, clickY, childAbsX, childAbsY) then
                return true
            end
        end
    end
    return false
end

return Pane
