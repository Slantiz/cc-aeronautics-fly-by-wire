-- ==================================================
-- Wrapper over monitor which render/interact with modules
-- ==================================================

local Screen = {}
Screen.__index = Screen

function Screen.new(mon, data, config)
    mon.setTextScale(0.5)
    return setmetatable({
        mon     = mon,
        data    = data,
        config  = config,
        modules = {},
    }, Screen)
end

function Screen:mount(module, ox, oy, deps)
    local ctx = {
        mon    = self.mon,
        ox     = ox,
        oy     = oy,
        data   = self.data,
        config = self.config,
    }
    table.insert(self.modules, { module = module, ctx = ctx })
    module.init(ctx, deps or {})
end

function Screen:draw()
    self.mon.setBackgroundColor(colors.black)
    self.mon.clear()
    for _, m in ipairs(self.modules) do
        m.module.draw(m.ctx)
    end
end

function Screen:touch(x, y)
    for _, m in ipairs(self.modules) do
        local lx = x - m.ctx.ox + 1
        local ly = y - m.ctx.oy + 1
        if lx >= 1 and lx <= m.module.width and ly >= 1 and ly <= m.module.height then
            m.module.on_touch(m.ctx, lx, ly)
        end
    end
end

return Screen
