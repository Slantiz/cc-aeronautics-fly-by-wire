local rtuner = {}

local RelayTuner = {}
RelayTuner.__index = RelayTuner

-- h: relay output amplitude (e.g. elevator degrees to slam)
-- setpoint: the value we oscillate around (e.g. target pitch in deg)
-- cycles: how many full oscillations to measure before computing
function RelayTuner.new(h, setpoint, cycles)
    return setmetatable({
        h         = h,
        setpoint  = setpoint,
        cycles    = cycles or 6,
        _output   = h,        -- current relay output (+h or -h)
        _last_sign = nil,
        _crossings = {},      -- times of upward zero-crossings
        _peak      = 0,       -- max |error| seen this half-cycle
        _amps      = {},      -- recorded peak amplitudes
        _done      = false,
        _result    = nil,     -- { Ku, Tu, kp, ki, kd }
    }, RelayTuner)
end

-- call every tick; returns the relay output to apply to the actuator
function RelayTuner:tick(measured, now)
    local err = self.setpoint - measured

    -- track peak error magnitude within the current half-cycle
    if math.abs(err) > self._peak then self._peak = math.abs(err) end

    -- relay logic: flip output based on which side of setpoint we're on
    local sign = err > 0 and 1 or -1
    self._output = sign * self.h

    -- detect a sign flip = a zero crossing
    if self._last_sign ~= nil and sign ~= self._last_sign then
        -- on an upward crossing (neg->pos), we completed one full period
        if sign == 1 then
            table.insert(self._crossings, now)
            table.insert(self._amps, self._peak)
            self._peak = 0
            if #self._crossings >= self.cycles + 1 then
                self:_compute()
            end
        else
            -- downward crossing: also reset peak for the next half
            self._peak = 0
        end
    end
    self._last_sign = sign

    return self._output
end

function RelayTuner:_compute()
    -- average period from spacing between upward crossings
    local periods = {}
    for i = 2, #self._crossings do
        periods[#periods+1] = (self._crossings[i] - self._crossings[i-1]) / 1000  -- ms->s
    end
    -- discard the first couple cycles (transient), average the rest
    local function avg(t, from)
        local sum, n = 0, 0
        for i = from, #t do sum = sum + t[i]; n = n + 1 end
        return n > 0 and sum / n or 0
    end
    local Tu = avg(periods, math.max(1, #periods - 10))   -- last few periods
    local a  = avg(self._amps, math.max(1, #self._amps - 3))

    local Ku = (4 * self.h) / (math.pi * a)

    -- Ziegler-Nichols classic PID
    local kp = 0.6 * Ku
    local ki = 1.2 * Ku / Tu
    local kd = 0.075 * Ku * Tu

    self._result = { Ku = Ku, Tu = Tu, a = a, kp = kp, ki = ki, kd = kd }
    self._done = true
end

function RelayTuner:done()   return self._done end
function RelayTuner:result() return self._result end

rtuner.RelayTuner = RelayTuner
return rtuner
