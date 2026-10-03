local proto = {
    PROTOCOL    = "fcs",
    FC_HOST     = "flightcomputer",
    HUD_HOST    = "cockpit",
    -- HUD -> FC
    HELLO       = "hello",       -- handshake either way
    MODE        = "mode",        -- {mode="manual"|"cruise"|"approach"}
    INPUT       = "input",       -- {pitch,roll,yaw,throttle} (stream)
    COMMAND     = "command",
    TARGET      = "target",      -- {alt,spd,hdg}
    PARAM       = "param",       -- {key="pitch.kp", value=1.4}  live single
    CONFIG_PUSH = "config_push", -- {params=<whole table>}  ground setup
    CONFIG_REQ  = "config_req",  -- ask FC for its current params
    -- FC -> HUD
    CONFIG      = "config",      -- {params=<table>}  reply to CONFIG_REQ
    TELEMETRY   = "telemetry",   -- {alt,spd,hdg,pitch,roll,vs,fuel,...}
    ACK         = "ack",         -- {of=<type>, ok=bool, err=?, echo=<seq/ts>}
    ALERT       = "alert",       -- {level="warn"|"crit", msg="stall"}
}

function proto.input(pitch, roll, yaw, throttle)
    return { pitch = pitch, roll = roll, yaw = yaw, throttle = throttle }
end

proto.CMD = {
    GEAR_TOGGLE = "gear_toggle",
    RAMP_TOGGLE = "ramp_toggle",
    FLAPS_SET = "flaps_set"
}

function proto.command(cmd, value)
    return { cmd = cmd, value = value }
end

function proto.telemetry()
    return {
        alt = 0,
        spd_z = 0,
        spd_y = 0,
        spd_x = 0,
        pitch = 0,
        roll = 0,
        hdg = 0,
        elevators_a = 0,
        rudder_a = 0,
        ailerons_a = 0,
        flaps_a = 0,
        fuel = 0,
        e_spd = 0,
        p_spd = 0,
        stress = 0,
        pitch_i = 0,
        roll_i = 0,
        yaw_i = 0,
        throttle = 0,
        mode = "manual",
        lg_up = false,
        ramp_up = false
    }
end

return proto
