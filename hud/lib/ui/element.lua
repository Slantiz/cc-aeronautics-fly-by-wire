---@class Element
---@field x number
---@field y number
---@field w number
---@field h number
local Element = {}
Element.__index = Element

---Creates a new Element instance
---@param x? number
---@param y? number
---@param w? number
---@param h? number
---@return Element
function Element:new(x, y, w, h)
    local obj = setmetatable({}, self)
    obj.x = x or 0
    obj.y = y or 0
    obj.w = w or 1
    obj.h = h or 1
    return obj
end

---@param x number
---@param y number
---@return Element
function Element:setPos(x, y)
    self.x = x
    self.y = y
    return self -- Allows method chaining
end

---@param w number
---@param h number
---@return Element
function Element:setSize(w, h)
    assert(w >= 0 and h >= 0, "Width and height must be greater than or equal to 0")
    self.w = w
    self.h = h
    return self -- Allows method chaining
end

---@param _screen Screen
---@param _absX number
---@param _absY number
function Element:draw(_screen, _absX, _absY)
end

---@param _clickX number
---@param _clickY number
---@param _absX number
---@param _absY number
---@return boolean
function Element:handleClick(_clickX, _clickY, _absX, _absY)
    return false
end

return Element
