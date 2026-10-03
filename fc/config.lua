-- ==================================================
--
-- Fixed config. Should only need to be set up once.
--
-- ==================================================

local cfg = {}

cfg.modem = "bottom"

cfg.hud_id = 35

cfg.fuel_capacity = 64000

--
cfg.sign_axis = {
    elevators = 1,  -- Positive pitch -> nose up
    rudder    = -1, -- Positive yaw   -> yaw right
    flaps     = 1,  -- Positive flaps -> flaps down
    ailerons  = -1  -- Positive roll  -> roll clockwise
}

cfg.sensor_sign = {
    pitch = 1,  -- nose up positive
    roll  = -1, -- roll right positive
    spd_z = -1, -- forward positive
    spd_y = 1,  -- up positive
    spd_x = 1,  -- right positive
    hdg   = 1,  -- clockwise positive
}

cfg.signals = {
    relay_landing_gear = { relay = "relay_1", side = "front", analog = false },
    relay_ramp         = { relay = "relay_1", side = "bottom", analog = false },
    relay_turn_right   = { relay = "relay_2", side = "front", analog = true },
    relay_turn_left    = { relay = "relay_3", side = "front", analog = true },
}

cfg.nav_anchors = {
    { x = 0,     z = 0,     y = 110, nav = "nav_00" },
    { x = 10000, z = 0,     y = 110, nav = "nav_10" },
    { x = 0,     z = 10000, y = 110, nav = "nav_01" },
}

cfg.peripherals = {
    -- Sensors
    strs_mtr  = "Create_Stressometer_1",
    e_spd_mtr = "Create_Speedometer_2",
    p_spd_mtr = "Create_Speedometer_4",
    fuel_tank = "create:fluid_tank_3",

    -- Flight Sensors
    spd_sensor_z = "velocity_sensor_13",
    spd_sensor_y = "velocity_sensor_12",
    spd_sensor_x = "velocity_sensor_9",
    alt_sensor   = "altitude_sensor_8",
    gim_sensor   = "gimbal_sensor_5",
    nav_00       = "navigation_table_7",
    nav_10       = "navigation_table_6",
    nav_01       = "navigation_table_5",
    nav_n        = "navigation_table_8",

    -- Relays
    relay_1 = "redstone_relay_9",
    relay_2 = "redstone_relay_7",
    relay_3 = "redstone_relay_8",

    -- Throttle
    rsc_throttle = "Create_RotationSpeedController_18",

    -- Control Surfaces
    rsc_elevators    = "Create_RotationSpeedController_3",
    swivel_elevators = "swivel_bearing_15",
    rsc_rudder       = "Create_RotationSpeedController_4",
    swivel_rudder    = "swivel_bearing_14",
    rsc_flaps        = "Create_RotationSpeedController_19",
    swivel_flaps     = "swivel_bearing_22",
    rsc_ailerons     = "Create_RotationSpeedController_11",
    swivel_ailerons  = "swivel_bearing_21",
}

return cfg
