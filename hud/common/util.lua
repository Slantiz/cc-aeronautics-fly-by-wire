local util = {}

-- ==================================================
--
-- Math
--
-- ==================================================

function util.clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

function util.remap(val, in_min, in_max, out_min, out_max)
    return out_min + (val - in_min) / (in_max - in_min) * (out_max - out_min)
end

-- combined
function util.clamp_round(val, min, max)
    return math.floor(util.clamp(val, min, max) + 0.5)
end

function util.deg_to_rad(deg)
    return deg * (math.pi / 180)
end

function util.rad_to_deg(rad)
    return rad * (180 / math.pi)
end

function util.lerp(a, b, t)
    return a + (b - a) * t
end

-- ==================================================
--
-- Scrollable logging (per-target scroll state)
--
-- ==================================================

local PREFIX = #("[00:00:00] ")

local Log = {}
Log.__index = Log

function Log.new()
    return setmetatable({
        created = os.date("%Y-%m-%d %H:%M:%S"),
        history = {},
        _cache = {}, -- [width] = { rows = {...}, done = N }
        _t = {},     -- [key]   = { scroll, region, live, width }
        dirty = true,
    }, Log)
end

util.Log = Log

local function wrap_entry(text, w)
    if text == "" then return { "" } end
    local out = { text:sub(1, w - PREFIX) }
    text = text:sub(w - PREFIX + 1)
    while #text > 0 do
        out[#out + 1] = text:sub(1, w)
        text = text:sub(w + 1)
    end
    return out
end

local function get_rows(self, w)
    local c = self._cache[w]
    if not c then
        c = { rows = {}, done = 0 }; self._cache[w] = c
    end
    if c.done > #self.history then c.rows, c.done = {}, 0 end
    while c.done < #self.history do
        local e = self.history[c.done + 1]
        for j, txt in ipairs(wrap_entry(e.text, w)) do
            c.rows[#c.rows + 1] = { time = e.time, color = e.color, text = txt, head = (j == 1) }
        end
        c.done = c.done + 1
    end
    return c.rows
end

local function max_scroll(self, target)
    local w, h = target.getSize()
    return math.max(0, #get_rows(self, w) - h)
end

local function tstate(self, key, live)
    local st = self._t[key]
    if not st then
        st = { scroll = 0, region = nil, live = live or false, width = nil }
        self._t[key] = st
    end
    return st
end

local function emit(self, s, color)
    local text = tostring(s)
    self.history[#self.history + 1] = { time = os.date("%H:%M:%S"), text = text, color = color }
    for _, st in pairs(self._t) do
        -- hold scrolled-up views in place: bump by THIS view's wrapped row count
        if not st.live and st.scroll > 0 and st.width then
            st.scroll = st.scroll + #wrap_entry(text, st.width)
        end
    end
    self.dirty = true
end

function Log:info(s) emit(self, s, colors.white) end

function Log:warn(s) emit(self, s, colors.yellow) end

function Log:error(s) emit(self, s, colors.red) end

-- target: display; key: per-target id; live: pin to bottom (never scrolls)
function Log:redraw(target, key, live)
    target = target or term.current()
    key = key or "term"
    local st = tstate(self, key, live)
    if st.live then st.scroll = 0 end

    local w, h = target.getSize()
    st.width = w -- remember for emit's per-view bump
    local rows = get_rows(self, w)
    local first = math.max(1, #rows - h + 1 - st.scroll)

    target.setBackgroundColor(colors.black)
    target.clear()
    for i = first, math.min(#rows, first + h - 1) do
        local r = rows[i]
        local y = i - first + 1
        target.setCursorPos(1, y)
        if r.head then
            target.setTextColor(colors.gray)
            target.write(("[%s] "):format(r.time))
        end
        target.setTextColor(r.color)
        target.write(r.text)
    end

    st.region = nil
    if st.scroll > 0 then
        local label = ("[-%d] [jump]"):format(st.scroll)
        local x = w - #label + 1
        target.setCursorPos(x, 1)
        target.setBackgroundColor(colors.gray)
        target.setTextColor(colors.white)
        target.write(label)
        target.setBackgroundColor(colors.black)
        st.region = { x = x, y = 1, x2 = w }
    end
    target.setTextColor(colors.white)
    return rows, st.region
end

function Log:on_click(x, y, key)
    local st = self._t[key or "term"]
    local r = st and st.region
    if r and y == r.y and x >= r.x and x <= r.x2 then
        st.scroll = 0
        self.dirty = true
        return true
    end
    return false
end

function Log:on_scroll(dir, target, key)
    local st = tstate(self, key or "term")
    if st.live then return end
    st.scroll = math.max(0, math.min(st.scroll - dir, max_scroll(self, target)))
    self.dirty = true
end

-- jump a view to live (used on exit, etc.)
function Log:jump(key)
    local st = self._t[key or "term"]
    if st then
        st.scroll = 0; self.dirty = true
    end
end

-- ==================================================
--
-- Redstone signals class
--
-- ==================================================

local Signal = {}
Signal.__index = Signal

function Signal.new(relay, side, analog)
    return setmetatable({
        relay        = relay,
        side         = side,
        analog       = analog,
        _desired     = analog and 0 or false,
        _last        = nil,
        _pulse_ticks = 0,
    }, Signal)
end

util.Signal = Signal

-- Instant setter — no peripheral write
function Signal:set(v)
    self._desired = v
end

-- Queues a pulse; apply() will hold it high for `ticks` ticks then drop it
function Signal:pulse(ticks)
    self._desired     = self.analog and 15 or true
    self._pulse_ticks = ticks or 1
end

-- Blocking — call from ticker only
function Signal:tick()
    if self._pulse_ticks > 0 then
        self._pulse_ticks = self._pulse_ticks - 1
        if self._pulse_ticks == 0 then
            self._desired = self.analog and 0 or false
        end
    end

    if self._desired ~= self._last then
        if self.analog then
            self.relay.setAnalogOutput(self.side, self._desired)
        else
            self.relay.setOutput(self.side, self._desired and true or false)
        end
        self._last = self._desired
    end
end

-- Reads the last desired value without hitting the peripheral
function Signal:get()
    return self._desired
end

-- ==================================================
--
-- Peripherals
--
-- ==================================================

function util.load_peripherals(periphs)
    local dev = {}
    for name, side in pairs(periphs) do
        dev[name] = peripheral.wrap(side)
        assert(dev[name], "missing peripheral: " .. name .. " (" .. side .. ")")
    end
    return dev
end

function util.load_signals(signals, dev)
    local sig = {}
    for name, def in pairs(signals) do
        local relay = dev[def.relay]
        assert(relay, "signal '" .. name .. "' -> unknown relay '" .. tostring(def.relay) .. "'")
        sig[name] = util.Signal.new(relay, def.side, def.analog)
    end
    return sig
end

-- ==================================================
--
-- Servo for control surfaces
--
-- ==================================================

-- function util.create_pid(kp, ki, kd, bias)
--     local pid = {
--         kp = kp,
--         ki = ki,
--         kd = kd,
--         bias = bias,
--         error_prior = 0,
--         integral_prior = 0,
--         tick = function(self, setpoint, getpoint, strength_mult, DT)
--             local kp = self.kp * strength_mult
--             local ki = self.ki * strength_mult
--             local kd = self.kd * strength_mult

--             local setRps = setpoint
--             local getRps = getpoint

--             local error = setRps - getRps
--             local integral = self.integral_prior + error * DT
--             local derivative = (error - self.error_prior) / DT

--             local value_out = kp * error + ki * integral + kd * derivative + self.bias

--             self.error_prior = error
--             self.integral_prior = integral

--             return value_out
--         end
--     }

--     return pid
-- end

-- ==================================================
-- Servo for control surfaces
-- ==================================================

local Servo = {}
Servo.__index = Servo

function Servo.new(rsc, bearing, strength, sign, axis_sign, min_angle, max_angle)
    assert(rsc, "provided RSC is nil")
    assert(bearing, "provided swivel bearing is nil")
    rsc.setTargetSpeed(0)
    return setmetatable({
        rsc = rsc,
        bearing = bearing,
        strength = strength,
        sign = sign,
        axis_sign = axis_sign,
        min_angle = min_angle,
        max_angle = max_angle,
        t_angle = 0,
    }, Servo)
end

util.Servo = Servo

-- This function yields. Use it in a coroutine!
function Servo:tick()
    -- P-controller step
    local error = self.t_angle - self.bearing.getTargetAngle()
    local val = error * self.strength
    local rpm = util.clamp(val, -48, 48) -- 48 is maximum to avoid overstressing

    self.rsc.setTargetSpeed(rpm * self.sign)
end

function Servo:set_angle(angle)
    self.t_angle = util.clamp(angle * self.axis_sign, -self.max_angle, self.max_angle)
end

function Servo:set_strength(strength)
    self.strength = strength
end

-- ==================================================
-- Throttle
-- ==================================================

local Throttle   = {}
Throttle.__index = Throttle

function Throttle.new(rsc, ramp_per_tick)
    assert(rsc, "provided RSC is nil")
    return setmetatable({ rsc = rsc, ramp_per_tick = ramp_per_tick, target = 0, last = nil }, Throttle)
end

util.Throttle = Throttle

-- This function yields. Use it in a coroutine!
function Throttle:apply()
    if self.target ~= self.last then
        local last = self.last or 0
        local step = util.clamp(self.target - last, -self.ramp_per_tick, self.ramp_per_tick)
        local new = last + step
        self.rsc.setTargetSpeed(new)
        self.last = new
    end
end

function Throttle:set(v) self.target = v end

-- function util.create_servo(controller, bearing, strength, pos_dir)
--     controller.setTargetSpeed(0)
--     local servo = {
--         controller = controller,
--         bearing = bearing,
--         desiredangle = bearing.getTargetAngle(),
--         angle = bearing.getTargetAngle(),
--         pos_dir = pos_dir or 1,
--         RPM = 0,
--         PID = create_pid(strength or 0.7, 0, 0, 0),
--         tick = function(self, DT) --WARNING: Calling this causes 50ms delay due to peripheral calls. Multithread this function to prevent your program from slowing to a crawl
--             self.angle = self.bearing.getTargetAngle()
--             local RPM = self.PID:tick(self.angle, self.desiredangle, 1, DT)
--             self.RPM = clamp(RPM, -48, 48)
--             self.controller.setTargetSpeed(self.RPM)
--         end,
--         set_angle = function(self, angle)
--             self.desiredangle = angle * pos_dir
--         end,
--     }
--     return servo
-- end

return util
