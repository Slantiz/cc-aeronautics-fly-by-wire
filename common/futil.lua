local futil = {}

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
	if self.i_limit then
		self._integral = math.max(-self.i_limit, math.min(self.i_limit, self._integral))
	end

	local out = p_term + self._integral + d_term + self.bias
	if self.out_min then
		out = math.max(self.out_min, out)
	end
	if self.out_max then
		out = math.min(self.out_max, out)
	end
	return out
end

futil.PID = PID

local Servo = {}
Servo.__index = Servo

function Servo.new(rsc, bearing, sign, axis_sign, min_angle, max_angle)
	assert(rsc, "provided RSC is nil")
	assert(bearing, "provided swivel bearing is nil")
	rsc.setTargetSpeed(0)
	return setmetatable({
		rsc = rsc,
		bearing = bearing,
		sign = sign,
		axis_sign = axis_sign,
		min_angle = min_angle,
		max_angle = max_angle,
		step = step or 0.6,
		max_rpm = max_rpm or 48,
		t_angle = 0,
		_last_rpm = 0,
	}, Servo)
end

Servo = Servo

-- This function yields. Use it in a coroutine!
function Servo:tick()
	local read = self.bearing.getTargetAngle()
	local target = self.t_angle * self.axis_sign
	local current_est = read + self._last_rpm * self.sign * self.step
	local error = target - current_est

	local rpm = util.clamp(error / (self.sign * self.step), -self.max_rpm, self.max_rpm)
	rpm = math.floor(rpm + 0.5)

	self.rsc.setTargetSpeed(rpm)
	self._last_rpm = rpm
end

function Servo:set_angle(angle)
	self.t_angle = util.clamp(angle, -self.max_angle, self.max_angle)
end

function Servo:set_strength(strength)
	self.strength = strength
end

return futil
