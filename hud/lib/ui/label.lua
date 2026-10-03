local Element = require("lib.ui.element")

---@class Label : Element
---@field text string
---@field color number
---@field bgColor number
local Label = setmetatable({}, Element)
Label.__index = Label

---@param x? number
---@param y? number
---@param text? string
---@param color? number
---@param bgColor? number
---@return Label
function Label:new(x, y, text, color, bgColor)
    local obj = Element.new(self, x, y, #(text or ""), 1) --[[@as Label]]
    obj.text = text or ""
    obj.color = color or colors.white
    obj.bgColor = bgColor or colors.black
    return obj
end

---@param screen Screen
---@param absX number
---@param absY number
function Label:draw(screen, absX, absY)
    local t = screen.target
    local oldText = t.getTextColor()
    local oldBg = t.getBackgroundColor()

    t.setTextColor(self.color)
    t.setBackgroundColor(self.bgColor)
    t.setCursorPos(absX, absY)
    t.write(self.text)

    t.setTextColor(oldText)
    t.setBackgroundColor(oldBg)
end

return Label
