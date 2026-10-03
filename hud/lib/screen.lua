---@class Screen
---@field target table   buffered window all panes draw into
---@field win table      same window (exposed for frame presentation)
---@field w number
---@field h number
---@field panes Pane[]
local Screen = {}
Screen.__index = Screen

---@param target table
---@return Screen
function Screen:new(target)
    local obj = setmetatable({}, self)
    local parent = target or term.current()
    obj.w, obj.h = parent.getSize()
    -- Panes draw into an off-screen window buffer instead of the live terminal.
    -- The whole frame is then presented at once (see Screen:draw), which removes
    -- the flicker/tearing you get from writing moving content straight to screen.
    obj.win = window.create(parent, 1, 1, obj.w, obj.h, true)
    obj.target = obj.win
    obj.panes = {}
    return obj
end

---@param pane Pane
---@return Screen
function Screen:addPane(pane)
    table.insert(self.panes, pane)
    return self
end

function Screen:draw()
    -- hide the window while drawing so partial updates never reach the terminal,
    -- then flush the finished frame in one go
    self.win.setVisible(false)
    for _, pane in ipairs(self.panes) do
        if pane.isVisible then
            pane:draw(self, pane.x, pane.y)
        end
    end
    self.win.setVisible(true)
end

---@param event string
---@param _p1 any
---@param p2 any
---@param p3 any
function Screen:handleEvent(event, _p1, p2, p3)
    local clickX, clickY
    if event == "mouse_click" then
        clickX, clickY = p2, p3
    elseif event == "monitor_touch" then
        clickX, clickY = p2, p3
    else
        return
    end

    for _, pane in ipairs(self.panes) do
        if pane.isVisible
        and clickX >= pane.x and clickX <= pane.x + pane.w - 1
        and clickY >= pane.y and clickY <= pane.y + pane.h - 1 then
            if pane:handleClick(clickX, clickY, pane.x, pane.y) then
                return
            end
        end
    end
end

return Screen
