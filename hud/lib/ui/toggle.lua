local Button = require("lib.ui.button")

---@class Toggle : Button
---@field on boolean
---@field activeColor number
local Toggle = setmetatable({}, Button)
Toggle.__index = Toggle

-- A Button that holds an on/off state: its background is `activeColor` when on
-- and gray when off. Clicking flips the state; owners read `.on`.
---@param x number
---@param y number
---@param w number
---@param h number
---@param text string
---@param activeColor number  background colour when on
---@param on? boolean         initial state (default true)
---@return Toggle
function Toggle:new(x, y, w, h, text, activeColor, on)
    local obj = Button.new(self, x, y, w, h, text) --[[@as Toggle]]
    obj.activeColor = activeColor or colors.green
    obj.on = on ~= false
    return obj
end

---@param screen Screen
---@param absX number
---@param absY number
function Toggle:draw(screen, absX, absY)
    self.bgColor = self.on and self.activeColor or colors.gray
    Button.draw(self, screen, absX, absY)
end

---@return boolean
function Toggle:handleClick()
    self.on = not self.on
    return true
end

return Toggle
