local Element = require("lib.ui.element")

---@class Button : Element
---@field text string
---@field callback function
---@field bgColor number
local Button = setmetatable({}, Element)
Button.__index = Button

---Creates a new Button instance
---@param x? number
---@param y? number
---@param w? number
---@param h? number
---@param text? string
---@return self
function Button:new(x, y, w, h, text, callback)
    local obj = Element.new(self, x, y, w, h) --[[@as Button]]
    obj.text = text or ""
    obj.callback = callback
    obj.bgColor = colors.gray
    return obj
end

---@param screen Screen
---@param absX number
---@param absY number
function Button:draw(screen, absX, absY)
    local t = screen.target
    local oldText = t.getTextColor()
    local oldBg = t.getBackgroundColor()

    t.setBackgroundColor(self.bgColor)
    t.setTextColor(colors.white)

    for row = 0, self.h - 1 do
        t.setCursorPos(absX, absY + row)
        t.write(string.rep(" ", self.w))
    end

    local textX = absX + math.floor((self.w - #self.text) / 2)
    local textY = absY + math.floor(self.h / 2)
    t.setCursorPos(textX, textY)
    t.write(self.text)

    t.setTextColor(oldText)
    t.setBackgroundColor(oldBg)
end

---@param _clickX number
---@param _clickY number
---@param _absX number
---@param _absY number
---@return boolean
function Button:handleClick(_clickX, _clickY, _absX, _absY)
    if self.callback then self.callback() end
    return true
end

return Button
