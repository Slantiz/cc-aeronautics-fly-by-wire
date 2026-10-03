local util    = require("render.util")

local M       = {}
M.width       = 12
M.height      = 3

local MODES   = { "manual", "cruise", "tuner" }
local buttons = {}
local deps    = {}

function M.init(ctx, d)
    deps = d -- expects deps.set_mode(mode)
    buttons = {}
    for i, mode in ipairs(MODES) do
        buttons[i] = util.Button.new(mode, 1, i, M.width, function()
            if deps.set_mode then deps.set_mode(mode) end
        end)
    end
end

function M.draw(ctx)
    local current = ctx.data.telemetry and ctx.data.telemetry.mode or ctx.data.mode
    for _, btn in ipairs(buttons) do
        local active = btn.label == current
        btn:draw(ctx.mon, ctx.ox, ctx.oy,
            active and colors.black or colors.white,
            active and colors.green or colors.gray)
    end
end

function M.on_touch(ctx, x, y)
    for _, btn in ipairs(buttons) do
        if y == btn.y and x >= btn.x and x < btn.x + btn.width then
            btn.callback()
        end
    end
end

return M
