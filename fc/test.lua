local config = require("config")
local rsc_elevators = peripheral.wrap(config.rsc_elevators)
local rsc_rudder = peripheral.wrap(config.rsc_rudder)
local rsc_flaps = peripheral.wrap(config.rsc_flaps)
local rsc_ailerons = peripheral.wrap(config.rsc_ailerons)
local swivel_elevators = peripheral.wrap(config.swivel_elevators)
local swivel_rudder = peripheral.wrap(config.swivel_rudder)
local swivel_flaps = peripheral.wrap(config.swivel_flaps)
local swivel_ailerons = peripheral.wrap(config.swivel_ailerons)

local servofactory = require("servo")
local servo_elevators = servofactory.create_servo(rsc_elevators, swivel_elevators, 1)
local servo_rudder = servofactory.create_servo(rsc_rudder, swivel_rudder, -1)
local servo_flaps = servofactory.create_servo(rsc_flaps, swivel_flaps, 1)
local servo_ailerons = servofactory.create_servo(rsc_ailerons, swivel_ailerons, -1)

local function setAll(a)
	servo_elevators:set_angle(a)
	servo_rudder:set_angle(a)
	servo_flaps:set_angle(a)
	servo_ailerons:set_angle(a)
end

math.randomseed(os.epoch("utc"))
RUN = true
DELTA_TIME = 0.05 --seconds
DWELL = 0.5

local function ticker()
	while RUN do
		parallel.waitForAll(
			function() sleep(DELTA_TIME) end,
			function() servo_elevators:tick(DELTA_TIME) end,
			function() servo_rudder:tick(DELTA_TIME) end,
			function() servo_flaps:tick(DELTA_TIME) end,
			function() servo_ailerons:tick(DELTA_TIME) end
		)
	end
end

-- setAll(0)

local function scheduler()
	sleep(2)
	setAll(0)
	for _ = 1, 5 do
		-- Test fast move to positions & dwell
		for _, a in ipairs({ -45, 45, 0 }) do
			setAll(a)
			sleep(DWELL)
		end

		-- Test smooth rotation
		for a = 0, 60 do
			setAll(a)
			sleep(DELTA_TIME)
		end
		for a = 60, -60, -1 do
			setAll(a)
			sleep(DELTA_TIME)
		end
		for a = -60, 0 do
			setAll(a)
			sleep(DELTA_TIME)
		end

		-- Test aggressive random rotation
		local t = {}
		for i = 1, 100 do
			t[i] = math.random(-90, 90)
		end
		for i = 1, #t do
			setAll(t[i])
			sleep(DELTA_TIME)
		end
		setAll(0)
		sleep(DWELL)
	end
	sleep(2)
	RUN = false
end

parallel.waitForAll(ticker, scheduler)