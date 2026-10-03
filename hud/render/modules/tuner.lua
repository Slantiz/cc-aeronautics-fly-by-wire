local util    = require("render.util")
local M       = {}
M.width       = 26
M.height      = 12

local fields  = {} -- the spec passed in at mount
local buttons = {}
local deps    = {}

function M.init(ctx, d)
    deps    = d             -- deps.set_param(key, value)
    fields  = d.fields or {} -- { {label, key, step}, ... }
    buttons = {}
    for i, f in ipairs(fields) do
        local y = i
        buttons[#buttons + 1] = util.Button.new("-", 18, y, 3, function()
            local cur = ctx.data.config and ctx.data.config[f.key] or 0
            deps.set_param(f.key, cur - f.step)
        end)
        buttons[#buttons + 1] = util.Button.new("+", 22, y, 3, function()
            local cur = ctx.data.config and ctx.data.config[f.key] or 0
            deps.set_param(f.key, cur + f.step)
        end)
    end
end

function M.draw(ctx)
    local cfg = ctx.data.config
    for i, f in ipairs(fields) do
        local y = ctx.oy + i - 1
        local val = cfg and cfg[f.key]
        local txt = val ~= nil and string.format("%.3g", val) or "--"
        util.write_at(ctx.mon, ctx.ox, y, string.format("%-9s %6s", f.label, txt), colors.white, colors.black)
    end
    for _, b in ipairs(buttons) do b:draw(ctx.mon, ctx.ox, ctx.oy) end
end

function M.on_touch(ctx, x, y)
    for _, b in ipairs(buttons) do
        if y == b.y and x >= b.x and x < b.x + b.width then b.callback() end
    end
end

return M
