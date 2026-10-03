package.path = "/common/?.lua;" .. package.path

-- ==================================================
-- Load modules & initialize
-- ==================================================

local util   = require("util")
local futil  = require("flight.util")
local cfg    = require("config")
local proto  = require("proto")
local Net    = require("net")
local Params = require("params")
local resect = require("flight.resect")

settings.load()

local log = util.Log.new()
log:info("Initializing...")
local dev = util.load_peripherals(cfg.peripherals)
local sig = util.load_signals(cfg.signals, dev)
local params = Params.new()

assert(Net.open(cfg.modem))
assert(cfg.hud_id, "cfg.hud_id (cockpit's computer ID) is not set")
local hud = Net.new(cfg.hud_id)

log:attach("term", term.current())

local DT            = 0.05
local THROTTLE_RAMP = 5

-- ==================================================
-- Actuators
-- ==================================================

local throttle        = futil.Throttle.new(dev.rsc_throttle, THROTTLE_RAMP)
local servo_elevators = futil.Servo.new(dev.rsc_elevators, dev.swivel_elevators, -1, cfg.sign_axis.elevators, -45, 45)
local servo_ailerons  = futil.Servo.new(dev.rsc_ailerons, dev.swivel_ailerons, 1, cfg.sign_axis.ailerons, -45, 45)
local servo_rudder    = futil.Servo.new(dev.rsc_rudder, dev.swivel_rudder, 1, cfg.sign_axis.rudder, -45, 45)
local servo_flaps     = futil.Servo.new(dev.rsc_flaps, dev.swivel_flaps, -1, cfg.sign_axis.flaps, -45, 45)

-- ==================================================
-- State
-- ==================================================

local state = {
    mode = "manual",
    sensors = { -- the world
        alt     = 0,
        lat     = 0,
        lon     = 0,
        spd_z   = 0,
        spd_y   = 0,
        spd_x   = 0,
        pitch   = 0,
        roll    = 0,
        hdg     = 0,
        e_spd   = 0,
        p_spd   = 0,
        stress  = 0,
        fuel    = 0,
        nav00   = 0,
        nav01   = 0,
        nav10   = 0,
        nav_nor = 0,
    },
    input = { pitch = 0, roll = 0, yaw = 0, throttle = 0 }, -- the pilot
    target = { alt = 0, spd = 0, hdg = 0 },                 -- the goal
    lg_up = false,
    ramp_up = false,
    alerts = { stall = false, bankangle = false, fuel = false },
    last_input = 0,
    last_rx = 0,
}

-- ==================================================
-- Helpers
-- ==================================================

local count = 0

-- Reads sensor data into state
local function read_sensors()
    local sgn = cfg.sensor_sign

    local s = state.sensors
    parallel.waitForAll(
        function() s.alt = dev.alt_sensor.getHeight() end,
        function() s.spd_z = dev.spd_sensor_z.getVelocity() * sgn.spd_z end,
        function() s.spd_y = dev.spd_sensor_y.getVelocity() * sgn.spd_y end,
        function() s.spd_x = dev.spd_sensor_x.getVelocity() * sgn.spd_x end,
        function()
            local a = dev.gim_sensor.getAngles()
            s.pitch, s.roll = a[2] * sgn.pitch, a[1] * sgn.roll
        end,
        function() s.e_spd = dev.e_spd_mtr.getSpeed() end,
        function() s.p_spd = dev.p_spd_mtr.getSpeed() end,
        function() s.stress = dev.strs_mtr.getStress() end,
        function() s.nav_00 = dev.nav_00.getRelativeAngle() end,
        function() s.nav_10 = dev.nav_10.getRelativeAngle() end,
        function() s.nav_01 = dev.nav_01.getRelativeAngle() end,
        function() s.nav_n = dev.nav_n.getRelativeAngle() end,
        function() servo_elevators:sense() end,
        function() servo_ailerons:sense() end,
        function() servo_rudder:sense() end,
        function() servo_flaps:sense() end
    -- Fill more sensor functions here
    )
    -- Derive values here
    -- s.vspd, s.hspd = decompose(s.vel) ...

    state.sensors = s

    -- GPS
    local bearings = {}
    for _, anchor in ipairs(cfg.nav_anchors) do
        table.insert(bearings, {
            x = anchor.x,
            y = anchor.y,
            z = anchor.z,
            bearing = s[anchor.nav]
        })
    end

    local x, z, h, r = resect.resect3(bearings, s.nav_n, s.roll, -s.pitch, s.alt)
    s.lon = x
    s.lat = z
    s.hdg = h

    if count % 10 == 0 then
        log:info(("hdg %.2f, x %.2f, z %.2f, alt %.2f"):format(s.hdg, s.lon, s.lat, s.alt))
    end
    count = count + 1
end

-- Wraps state into a telemetry object ready to be sent
function make_telemetry()
    local t = proto.telemetry()
    local s = state.sensors
    t.alt = s.alt
    t.lat = s.lat
    t.lon = s.lon
    t.spd_z = s.spd_z
    t.spd_y = s.spd_y
    t.spd_x = s.spd_x
    t.pitch = s.pitch
    t.roll = s.roll
    t.hdg = s.hdg
    t.elevators_a = servo_elevators.t_angle
    t.rudder_a = servo_rudder.t_angle
    t.ailerons_a = servo_ailerons.t_angle
    t.flaps_a = servo_flaps.t_angle
    t.fuel = s.fuel
    t.e_spd = s.e_spd
    t.p_spd = s.p_spd
    t.stress = s.stress

    t.pitch_i = state.input.pitch
    t.roll_i = state.input.roll
    t.yaw_i = state.input.yaw
    t.throttle = state.input.throttle

    t.mode = state.mode
    t.lg_up = state.lg_up
    t.ramp_up = state.ramp_up
    return t
end

-- Map a normalized INPUT message to actuators. Instant setters only —
-- the blocking writes happen in the tick block.
local function drive_direct(input)
    servo_elevators:set_angle(input.pitch * params.max_deflection)
    servo_ailerons:set_angle(input.roll * params.max_deflection)
    servo_rudder:set_angle(input.yaw * params.max_deflection)
    throttle:set(input.throttle * params.throttle_max)

    local spd = math.abs(state.sensors.spd_z)
    local steer_strength = util.clamp(util.remap(spd, 0, 50, 15, 5), 5, 15)
    local steer_val = math.floor(steer_strength + 0.5) -- round
    sig.relay_turn_left:set(input.roll < 0 and steer_val or 0)
    sig.relay_turn_right:set(input.roll > 0 and steer_val or 0)
end

-- ==================================================
-- Modes
-- ==================================================

local pid_alt = futil.PID.new(0.8, 0.05, 0.3, { i_limit = 15, out_min = -15, out_max = 15 })
local pid_pitch = futil.PID.new(1.5, 8, 0.5, { i_limit = 5, out_min = -45, out_max = 45 })
local pid_roll = futil.PID.new(1.5, 0, 0, { i_limit = 1, out_min = -45, out_max = 45 })

local modes = {
    manual = {
        enter = function() end,
        tick = function(dt) drive_direct(state.input) end,
        exit = function() end,
    },
    cruise = {
        enter = function()
            pid_alt:reset()
            pid_roll:reset()
            pid_pitch:reset()
            state.target.alt = 300
        end,
        tick = function(dt)
            -- Make the PIDs live-tunable
            t_alt           = state.target.alt
            pid_alt.kp      = params.cruise_alt_kp
            pid_alt.ti      = params.cruise_alt_ti
            pid_alt.td      = params.cruise_alt_td
            pid_alt.i_limit = params.cruise_alt_ilimit
            pid_alt.bias    = params.cruise_alt_bias

            pid_roll.kp      = params.cruise_roll_kp
            pid_roll.ti      = params.cruise_roll_ti
            pid_roll.td      = params.cruise_roll_td
            pid_roll.i_limit = params.cruise_roll_ilimit
            pid_roll.bias    = params.cruise_roll_bias

            pid_pitch.kp      = params.cruise_pitch_kp
            pid_pitch.ti      = params.cruise_pitch_ti
            pid_pitch.td      = params.cruise_pitch_td
            pid_pitch.i_limit = params.cruise_pitch_ilimit
            pid_pitch.bias    = params.cruise_pitch_bias

            local s = state.sensors

            -- Correct roll (P-controller)
            local ailerons_cmd = pid_roll:tick(0, s.roll, dt)
            servo_ailerons:set_angle(ailerons_cmd)

            -- Correct pitch based on height (Full PID-controller)
            local target_pitch = pid_alt:tick(t_alt, s.alt, dt)

            -- target_pitch = 10 + (t_alt - 200) / 50
            local elevators_cmd = pid_pitch:tick(target_pitch, s.pitch, dt, log)
            -- log:info(("%.3f, %.3f, %.3f"):format(elevators_cmd, target_pitch, s.pitch))
            servo_elevators:set_angle(elevators_cmd)

            -- log:info(("t_alt: %.2f, t_pch: %.3f, %.3f"):format(t_alt, target_pitch, pid_alt._integral))
            -- log:info(("t_pch: %.3f, pch I: %.3f, %.3f"):format(target_pitch, pid_pitch._integral, pid_roll._integral, elevators_cmd))

            -- throttle stays manual
            throttle:set(state.input.throttle * params.throttle_max)
        end,
        exit = function() end,
    },
}

local function set_mode(new)
    if not modes[new] then return false end
    if new == state.mode then return true end
    modes[state.mode].exit()
    state.mode = new
    modes[new].enter()
    return true
end

-- ==================================================
-- Scheduling & Control
-- ==================================================

-- Yielding peripheral calls are parallelized so that
-- they don't serialize, spanning multiple ticks.
local function ticker()
    parallel.waitForAll(
        function() servo_elevators:tick(log) end,
        function() servo_ailerons:tick() end,
        function() servo_rudder:tick() end,
        function() servo_flaps:tick() end,
        function() throttle:apply() end,
        function() sig.relay_turn_left:tick() end,
        function() sig.relay_turn_right:tick() end,
        function() sig.relay_landing_gear:tick() end,
        function() sig.relay_ramp:tick() end,
        function() sig.relay_ramp:tick() end,
        function() log:redraw_all() end,
        function() hud:send(proto.TELEMETRY, make_telemetry()) end
    )
end

-- Event scheduler.
-- This deals with receiving messages from the HUD controller
-- as well as other events.
local function scheduler()
    log:info("Scheduler started")
    while true do
        local event = { os.pullEventRaw() }
        local kind = event[1]

        if kind == "rednet_message" then
            local id, msg = event[2], event[3]
            if id == cfg.hud_id and type(msg) == "table" then
                state.last_rx = os.epoch("utc")
                local t = msg.t
                if t == proto.HELLO then
                    hud:send(proto.ACK, { of = proto.HELLO, ok = true, echo = msg.ts })
                elseif t == proto.CONFIG_REQ then
                    hud:send(proto.CONFIG, { params = params:snapshot() })
                    log:info("REQ: Sent param config")
                elseif t == proto.CONFIG_PUSH then
                    for k, v in pairs(msg.params) do
                        params:set(k, v)
                    end -- :set persists
                    hud:send(proto.ACK, { of = proto.CONFIG_PUSH, ok = true })
                    log:info("REQ: Overwrote param config")
                elseif t == proto.PARAM then
                    local ok = pcall(function() params:set(msg.key, msg.value) end)
                    hud:send(proto.CONFIG, { params = params:snapshot(), ok = true })
                    if ok then
                        log:info("REQ: Set " .. msg.key .. " -> " .. tostring(msg.value))
                    else
                        log:warn("REQ: Bad param: " .. tostring(msg.key))
                    end
                elseif t == proto.MODE then
                    local ok = set_mode(msg.mode)
                    hud:send(proto.ACK, { of = proto.MODE, ok = ok, err = ok and nil or "unknown mode" })
                    if ok then
                        log:info("REQ: Set mode -> " .. msg.mode)
                    else
                        log:warn("REQ: Rejected unknown mode -> " .. tostring(msg.mode))
                    end
                elseif t == proto.INPUT then
                    state.input = msg
                    state.last_input = os.epoch("utc")
                elseif t == proto.TARGET then
                    state.target = msg
                elseif t == proto.COMMAND then
                    local cmd = msg.cmd
                    local value = msg.value
                    if cmd == proto.CMD.GEAR_TOGGLE then
                        state.lg_up = not state.lg_up
                        sig.relay_landing_gear:pulse(10)
                        log:info("Gear " .. (state.lg_up and "up" or "down"))
                    elseif cmd == proto.CMD.RAMP_TOGGLE then
                        state.ramp_up = not state.ramp_up
                        sig.relay_ramp:pulse(10)
                        log:info("Ramp " .. (state.ramp_up and "up" or "down"))
                    elseif cmd == proto.CMD.FLAPS_SET then
                        servo_flaps:set_angle(value)
                        log:info("Flaps -> " .. tostring(value))
                    end
                    hud:send(proto.ACK, { of = proto.COMMAND, ok = true })
                end
            end
        elseif kind == "mouse_click" then
            log:on_click(event[3], event[4], "term")
        elseif kind == "mouse_scroll" then
            log:on_scroll(event[2], term.current(), "term")
        elseif kind == "key" then
            if event[2] == 261 then return end -- dev convenience
        end
    end
end

-- Control loop.
-- This drives flight computer functionality every tick.
-- It makes sure sensing, thinking and acting happen in order.
local function control_loop()
    local dt = 0.05
    local next_tick = os.startTimer(0)
    local frame = 0

    while true do
        -- next_tick = os.startTimer(0) -- Timer will hit next tick
        frame = frame + 1

        -- 1. SENSE: Read sensors and inputs (no yields)
        read_sensors()

        -- 2. THINK: Pure computation (no yields)
        modes[state.mode].tick(dt)

        -- 3. ACT: Issue peripheral writes (yields 1 tick)
        ticker()
    end
end




local function gauge_fuel()
    while true do
        -- This can't be read in read_sensors() as it tanks() yields.
        local tank = dev.fuel_tank.tanks()[1]
        if tank then
            state.sensors.fuel = tank.amount / cfg.fuel_capacity
        else
            state.sensors.fuel = 0
        end
        sleep(5)
    end
end

-- ==================================================
-- Program Lifetime & Crash Recovery
-- ==================================================

local function uninit()
    log:info("Uninitializing...")
    throttle:set(0)
    servo_elevators:set_angle(0)
    servo_ailerons:set_angle(0)
    servo_rudder:set_angle(0)
    servo_flaps:set_angle(0)
    -- Let the tick loop flush the above to peripherals for ~2 seconds
    log:redraw_all() -- flush logs before yielding
    parallel.waitForAny(function()
        while true do
            ticker()
        end
    end, function() sleep(1) end)
    log:info("Surfaces neutralized")
end

while true do
    local ok, err = pcall(function() parallel.waitForAny(scheduler, control_loop, gauge_fuel) end)

    log:info("FC stopping...")
    log:save("log.txt", false)

    if ok or err == "Terminated" then
        uninit()
        log:error("Terminated")
        log:clear_all("term") -- Clear all monitors except terminal
        log:settle("term")
        break
    end

    if err then log:error("Crash: " .. tostring(err)) end
    log:info("Restarting...")
    log:redraw_all()
    sleep(1)

    -- For dev purposes, i want to always see the error (no restart)
    break
end
