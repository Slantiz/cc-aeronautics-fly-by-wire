local util = require("common.util")

local futil = {}

-- ==================================================
-- PID
-- ==================================================

local PID = {}
PID.__index = PID

-- Standard form: out = Kp*(e + (1/Ti)*∫e + Td*de/dt) + bias
--   Ti = integral time  (seconds; LOWER = stronger integral; use math.huge to disable I)
--   Td = derivative time (seconds; HIGHER = more damping; 0 disables D)
function PID.new(kp, ti, td, opts)
    opts = opts or {}
    return setmetatable({
        kp = kp,
        ti = ti or math.huge, -- huge => no integral action
        td = td or 0,
        bias = opts.bias or 0,
        i_limit = opts.i_limit, -- max |integral term| in OUTPUT units (degrees)
        out_min = opts.out_min,
        out_max = opts.out_max,
        tt = opts.tt or ti or math.huge,
        _integral = 0, -- stored as the I CONTRIBUTION (output units)
        _prev_measured = nil,
    }, PID)
end

function PID:reset()
    self._integral = 0
    self._prev_measured = nil
end

function PID:tick(setpoint, measured, dt)
    local err = setpoint - measured

    -- Proportional
    local p_term = self.kp * err

    -- Derivative ON MEASUREMENT (no setpoint kick). Skip first tick.
    local d_term = 0
    if self._prev_measured then
        local dmeas = (measured - self._prev_measured) / dt
        d_term = -self.kp * self.td * dmeas
    end
    self._prev_measured = measured

    -- Integral: accumulate in OUTPUT units directly => Kp*(1/Ti)*∫e
    -- (storing the contribution makes i_limit a clean degree clamp)
    local i_inc = self.kp * (1 / self.ti) * err * dt

    -- Tentative output before committing the integral step
    local unsat = p_term + self._integral + i_inc + d_term + self.bias

    -- Conditional integration: only accept the increment if it doesn't push
    -- us further into output saturation (proper anti-windup).
    local saturated_high = self.out_max and unsat > self.out_max
    local saturated_low = self.out_min and unsat < self.out_min
    if not ((saturated_high and i_inc > 0) or (saturated_low and i_inc < 0)) then
        self._integral = self._integral + i_inc
    end

    -- Clamp the integral CONTRIBUTION to a degree limit
    if self.i_limit then self._integral = math.max(-self.i_limit, math.min(self.i_limit, self._integral)) end

    local out = p_term + self._integral + d_term + self.bias
    if self.out_min then out = math.max(self.out_min, out) end
    if self.out_max then out = math.min(self.out_max, out) end
    return out
end

-- function PID:tick(setpoint, measured, dt, log)
--     local err = setpoint - measured

--     -- Proportional
--     local p_term = self.kp * err

--     if log then log:info(("1. %.5f"):format(self._integral)) end

--     -- Derivative ON MEASUREMENT (no setpoint kick). Skip first tick.
--     local d_term = 0
--     if self._prev_measured then
--         local dmeas = (measured - self._prev_measured) / dt
--         d_term = -self.kp * self.td * dmeas
--     end
--     self._prev_measured = measured

--     -- Integral: accumulate in OUTPUT units directly => Kp*(1/Ti)*∫e
--     local i_inc = self.kp * (1 / self.ti) * err * dt
--     self._integral = self._integral + i_inc

--     if log then log:info(("2. %.5f"):format(self._integral)) end

--     -- Compute raw output
--     local out = p_term + self._integral + d_term + self.bias

--     -- Clamp output
--     local out_clamped = out
--     if self.out_min then out_clamped = math.max(self.out_min, out_clamped) end
--     if self.out_max then out_clamped = math.min(self.out_max, out_clamped) end

--     -- Back-calculate to unwind integral when saturating
--     local sat_error = out_clamped - out
--     if sat_error ~= 0 and self.tt and self.tt > 0 then
--         self._integral = self._integral + sat_error * (dt / self.tt)
--         if log then log:info(("b. %.5f"):format(self._integral)) end
--         -- if log then log:info(("backtracking chg: %.5f"):format(sat_error * (dt / self.tt))) end
--     end

--     -- Clamp integral AFTER back-calculation
--     if self.i_limit then
--         self._integral = math.max(-self.i_limit, math.min(self.i_limit, self._integral))
--     end

--     if log then log:info(("3. %.5f"):format(self._integral)) end

--     return out_clamped
-- end

futil.PID = PID

-- ==================================================
-- Servo
-- ==================================================

local Servo = {}
Servo.__index = Servo

function Servo.new(rsc, bearing, motion_dir, axis_sign, min_angle, max_angle, step, max_rpm)
    assert(rsc, "provided RSC is nil")
    assert(bearing, "provided swivel bearing is nil")
    rsc.setTargetSpeed(0)
    return setmetatable({
        rsc = rsc,
        bearing = bearing,
        motion_dir = motion_dir,
        axis_sign = axis_sign,
        min_angle = min_angle,
        max_angle = max_angle,
        step = step or 0.6,
        max_rpm = max_rpm or 48,
        t_angle = 0,
        _angle = 0,
        _last_rpm = 0,
    }, Servo)
end

futil.Servo = Servo

function Servo:sense() self._angle = self.bearing.getTargetAngle() end

function Servo:tick()
    local per_rpm = self.step * self.motion_dir
    local current = self._angle + self._last_rpm * per_rpm
    local target = self.t_angle * self.axis_sign
    local err = target - current
    local rpm = util.clamp(err / per_rpm, -self.max_rpm, self.max_rpm)
    rpm = math.floor(rpm + 0.5)
    self.rsc.setTargetSpeed(rpm)
    self._last_rpm = rpm
end

function Servo:set_angle(angle) self.t_angle = util.clamp(angle, self.min_angle, self.max_angle) end

-- ==================================================
-- Throttle
-- ==================================================

local Throttle = {}
Throttle.__index = Throttle

function Throttle.new(rsc, ramp_per_tick)
    assert(rsc, "provided RSC is nil")
    return setmetatable({ rsc = rsc, ramp_per_tick = ramp_per_tick, target = 0, last = nil }, Throttle)
end

futil.Throttle = Throttle

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

return futil
