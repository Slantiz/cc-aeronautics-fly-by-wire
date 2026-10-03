-- ==================================================
-- Tunable config which is persisted across reboot.
-- (See the .settings file.)
-- These are live-editable across rednet.
-- ==================================================

-- persist: "global" (one saved value) | "profile" (per active profile) | false (reset to default)
local SCHEMA = {
    strength       = { default = 1, persist = "global" },
    max_deflection = { default = 45, persist = "global" },
    throttle_max   = { default = 256, persist = "global" },
    pitch_trim     = { default = 0, persist = "profile" },
    roll_trim      = { default = 0, persist = "profile" },
    yaw_trim       = { default = 0, persist = "profile" },
    cruise_alt     = { default = 200, persist = "profile" },

    -- Cruise: altitude -> target pitch (outer loop)
    cruise_alt_kp       = { default = 0.8, persist = "profile" },
    cruise_alt_ti       = { default = 10, persist = "profile" },
    cruise_alt_td       = { default = 0.3, persist = "profile" },
    cruise_alt_ilimit   = { default = 8, persist = "profile" },
    cruise_alt_bias     = { default = 0, persist = "profile" },
    -- Cruise: pitch -> elevator (inner loop)
    cruise_pitch_kp     = { default = 1.5, persist = "profile" },
    cruise_pitch_ti     = { default = 10, persist = "profile" },
    cruise_pitch_td     = { default = 0.3, persist = "profile" },
    cruise_pitch_ilimit = { default = 5, persist = "profile" },
    cruise_pitch_bias   = { default = 7, persist = "profile" },

    cruise_roll_kp     = { default = 1.5, persist = "profile" },
    cruise_roll_ti     = { default = 10, persist = "profile" },
    cruise_roll_td     = { default = 0, persist = "profile" },
    cruise_roll_ilimit = { default = 0, persist = "profile" },
    cruise_roll_bias   = { default = 0, persist = "profile" },
}

local Params = {}
Params.__index = Params

function Params.new()
    local self = setmetatable({ _profile = settings.get("fc.profile", "default") }, Params)
    self:reload()
    return self
end

function Params:_key(name, def)
    if def.persist == "profile" then return "fc.prof." .. self._profile .. "." .. name end
    return "fc.glob." .. name
end

-- (Re)populate every field
function Params:reload()
    for name, def in pairs(SCHEMA) do
        self[name] = def.persist and settings.get(self:_key(name, def), def.default) or def.default
    end
end

-- The only write path
function Params:set(name, value)
    local def = assert(SCHEMA[name], "unknown param: " .. tostring(name))
    self[name] = value
    if def.persist then
        settings.set(self:_key(name, def), value); settings.save()
    end
end

-- Sets the profile
function Params:set_profile(name)
    self._profile = name
    settings.set("fc.profile", name); settings.save()
    self:reload()
end

-- For CONFIG over the wire
function Params:snapshot()
    local out = {}
    for name in pairs(SCHEMA) do out[name] = self[name] end
    return out
end

function Params:dump(log)
    log:info("-- PARAMS DUMP --")
    log:info("In-memory (SCHEMA fields):")
    for name in pairs(SCHEMA) do
        log:info(("  %s = %s"):format(name, tostring(self[name])))
    end
    log:info("Settings store (fc.* keys):")
    for _, k in ipairs(settings.getNames()) do
        if k:match("^fc%.") then
            local bare = k:match("^fc%.prof%.[^.]+%.(.+)$") or k:match("^fc%.glob%.(.+)$")
            local known = bare and SCHEMA[bare] and "" or "  <-- NOT IN SCHEMA"
            log:info(("  %s = %s%s"):format(k, tostring(settings.get(k)), known))
        end
    end
    log:info("-- END DUMP --")
end

return Params
