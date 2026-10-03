local Screen = require("lib.screen")

---@class Slate
---@field screens Screen[]
local Slate = {
    screens = {}
}

---@param target table
---@return Screen
function Slate:createScreen(target)
    local screen = Screen:new(target)
    table.insert(self.screens, screen)
    return screen
end

function Slate:start()
    local ok, err = xpcall(function()
        local function drawAll()
            for _, screen in ipairs(self.screens) do
                screen:draw()
            end
        end

        -- Redraw on a repeating timer rather than sleeping after each event.
        -- sleep() discards every event it isn't waiting for, which would drop
        -- mouse_click / monitor_touch and break clickable elements.
        drawAll()
        local frame = os.startTimer(0.05)
        while true do
            local event, p1, p2, p3 = os.pullEventRaw()
            if event == "terminate" then
                return
            elseif event == "timer" and p1 == frame then
                drawAll()
                frame = os.startTimer(0.05)
            else
                for _, screen in ipairs(self.screens) do
                    screen:handleEvent(event, p1, p2, p3)
                end
            end
        end
    end, debug.traceback)

    if not ok then
        local oldColor = term.getTextColor()
        term.setTextColor(colors.blue)
        print(err)
        term.setTextColor(oldColor)
    end
end

return Slate
