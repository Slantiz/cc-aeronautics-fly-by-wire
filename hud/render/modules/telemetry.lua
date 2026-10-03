local util = require("render.util")
local M    = {}
M.width    = 30
M.height   = 20

function M.init(ctx) end

function M.draw(ctx)
    local d = ctx.data.telemetry
    if not d then return end
    local fields = {
        { "ALT",   "%.2f",   d.alt },
        { "PCH",   "%.2f",   d.pitch },
        { "ROL",   "%.2f",   d.roll },
        { "HDG",   "%.2f",   d.hdg },
        { "FUEL",  "%.0f%%", (d.fuel or 0) * 100 },
        { "LON",   "%d",     d.lon},
        { "LAT",   "%d",     d.lat},
    }
    for i, f in ipairs(fields) do
        util.write_at(ctx.mon, ctx.ox, ctx.oy + i - 1,
            string.format("%-6s " .. f[2], f[1], f[3]),
            colors.white, colors.black)
    end
end

function M.on_touch(ctx, x, y) end

return M
