package.path        = "/common/?.lua;" .. package.path

-- ==================================================
-- Load util, config, settings, net, & init
-- ==================================================

local util          = require("util")
local cfg           = require("config")
local log           = util.Log.new()
local mod_telemetry = require("render.modules.telemetry")
local mod_mode      = require("render.modules.mode")
-- local Screen        = require("render.screen")
local proto         = require("proto")
local Net           = require("net")

local dev           = util.load_peripherals(cfg.peripherals)

dev.mon_main.setTextScale(0.5)
dev.mon_left.setTextScale(0.5)
dev.mon_right.setTextScale(0.5)

-- all displays the log renders to; nil targets are skipped everywhere
local renderTargets = {
    { target = term.current(), key = "term", live = false },
    -- { target = dev.mon_right,  key = "mon_right", live = true },
}


local state = {
    mode      = "manual",
    config    = nil, -- adopted from FC
    telemetry = nil, -- latest snapshot, for the HUD
    connected = false,
    last_rx   = 0,   -- epoch ms of last FC message
}

assert(Net.open(cfg.modem))
local fc = Net.new(cfg.fc_id)

-- local mon_main = Screen.new(dev.mon_main, state, nil)

-- mon_main:mount(mod_telemetry, 43, 1)
-- mon_main:mount(mod_mode, 30, 7, {
--     set_mode = function(mode)
--         fc:send(proto.MODE, { mode = mode })
--         log:info("CMD: Mode -> " .. mode)
--     end,
-- })
-- mon_main:mount(require("render.modules.tuner"), 1, 1, {
--     set_param = function(key, value)
--         fc:send(proto.PARAM, { key = key, value = value })
--     end,
--     fields = {
--         { label = "alt kp",   key = "cruise_alt_kp",       step = 0.05 },
--         { label = "alt ti",   key = "cruise_alt_ti",       step = 1 },
--         { label = "alt td",   key = "cruise_alt_td",       step = 0.1 },
--         { label = "alt ilim", key = "cruise_alt_ilimit",   step = 1 },
--         { label = "alt bias", key = "cruise_alt_bias",     step = 1 },
--         -- { label = "rol kp",   key = "cruise_roll_kp",     step = 0.1 },
--         -- { label = "rol ti",   key = "cruise_roll_ti",     step = 0.1 },
--         -- { label = "rol td",   key = "cruise_roll_td",     step = 0.1 },
--         -- { label = "rol ilim", key = "cruise_roll_ilimit", step = 0.5 },
--         -- { label = "rol bias", key = "cruise_roll_bias",   step = 0.5},
--         { label = "pch kp",   key = "cruise_pitch_kp",     step = 0.1 },
--         { label = "pch ti",   key = "cruise_pitch_ti",     step = 0.1 },
--         { label = "pch td",   key = "cruise_pitch_td",     step = 0.1 },
--         { label = "pch ilim", key = "cruise_pitch_ilimit", step = 1 },
--         { label = "pch bias", key = "cruise_pitch_bias",   step = 0.5 },
--     },
-- })

local hud_params = { pitch = 0, roll = 0, heading = 0, velocity = 0, altitude = 0, turnRadius = 0 }

local slate = require("lib.slate")
local Screen = require("lib.screen")
local Pane = require("lib.ui.pane")
local PFD = require("lib.ui.pfd")
local ND = require("lib.ui.nd")

-- print(dev.mon_main.getSize())
local screen = slate:createScreen(dev.mon_main)

local pane_pfd = Pane:new(39, 1, 19, 10)
local pfd = PFD:new(1, 1, 19, 10, hud_params)
pfd.debug = false
pfd.debugPriority = false
pane_pfd:add(pfd)

local pane_nd = Pane:new(23, 1, 15, 10)
local nd = ND:new(1, 1, 15, 10, hud_params)
pane_nd:add(nd)

screen:addPane(pane_pfd)
screen:addPane(pane_nd)

local function hud_parser()
    -- hud_params
    while true do
        local t = state.telemetry
        if t then
            hud_params.pitch = -t.pitch
            hud_params.roll = t.roll
            hud_params.heading = t.hdg
            hud_params.velocity = t.spd_z
            hud_params.altitude = t.alt
            hud_params.turnRadius = 0
        end
        sleep(0.05)
    end
end

-- ==================================================
-- Init
-- ==================================================

local function init()
    settings.load()
    log:info("Settings loaded.")

    -- Init network
    log:info("Connecting to FC.")
    local ok, msg = fc:wait_for(2)
    if not ok then
        log:warn("Failed to connect: " .. msg)
        return
    end
    state.connected = true
    state.last_rx = os.epoch("utc")
    log:info("Connected to FC.")


    local params, perr = fc:pull_config(2)
    if params then
        state.config = params
        log:info("Config pulled from FC.")
    else
        log:warn("No config: " .. tostring(perr))
    end
end

-- ==================================================
-- Util
-- ==================================================

local target_alt = 200

local prev = {}
local function take_input()
    local throttle = rs.getAnalogInput(cfg.rs.throttle)
    local codes = dev.typewriter.getPressedKeyCodes()
    local down = {}
    for _, code in ipairs(codes) do
        down[code] = true
    end

    local pitch_axis = 0
    local roll_axis = 0
    local yaw_axis = 0
    if down[keys.w] then
        pitch_axis = pitch_axis - 1
    end
    if down[keys.s] then
        pitch_axis = pitch_axis + 1
    end
    if down[keys.a] then
        roll_axis = roll_axis - 1
    end
    if down[keys.d] then
        roll_axis = roll_axis + 1
    end
    if down[keys.e] then
        yaw_axis = yaw_axis + 1
    end
    if down[keys.q] then
        yaw_axis = yaw_axis - 1
    end

    local function edge(key)
        local pressed = down[key] or false
        local was = prev[key] or false
        prev[key] = pressed
        return pressed and not was
    end

    if edge(keys.g) then
        fc:send(proto.COMMAND, proto.command(proto.CMD.GEAR_TOGGLE))
        log:info("CMD: Gear toggle")
    end
    if edge(keys.t) then
        fc:send(proto.COMMAND, proto.command(proto.CMD.RAMP_TOGGLE))
        log:info("CMD: Ramp toggle")
    end
    if edge(keys.f) then
        fc:send(proto.COMMAND, proto.command(proto.CMD.FLAPS_SET, 45))
        log:info("CMD: Flaps -> " .. tostring(45))
    end
    if edge(keys.c) then
        fc:send(proto.COMMAND, proto.command(proto.CMD.FLAPS_SET, 0))
        log:info("CMD: Flaps -> " .. tostring(0))
    end
    if edge(keys.up) then
        target_alt = target_alt + 50
        fc:send(proto.TARGET, { alt = target_alt })
        log:info("TARGET: alt -> " .. target_alt)
    end
    if edge(keys.down) then
        target_alt = target_alt - 50
        fc:send(proto.TARGET, { alt = target_alt })
        log:info("TARGET: alt -> " .. target_alt)
    end

    return {
        pitch = pitch_axis,
        roll = roll_axis,
        yaw = yaw_axis,
        throttle = throttle,
    }
end

-- ==================================================
--
-- Yielding functions which have to run in parallel
--
-- ==================================================

local function input_sender()
    log:info("Starting input sender.")
    while true do
        if state.connected and state.mode == "manual" then
            local inp = take_input()
            local inp_msg = proto.input(inp.pitch, inp.roll, inp.yaw, util.remap(inp.throttle, 0, 15, 0, 1))
            fc:send(proto.INPUT, inp_msg)
        end
        sleep(0.05)
    end
end

local function term_renderer()
    while true do
        -- Render log
        if log.dirty then
            log.dirty = false
            for _, t in ipairs(renderTargets) do
                if t.target then
                    log:redraw(t.target, t.key, t.live)
                end
            end
        end
        sleep(0.05)
    end
end

-- local function mon_renderer()
--     while true do
--         mon_main:draw()

--         sleep(0.05)
--     end
-- end

-- ==================================================
--
-- Main control loop
--
-- ==================================================

local function scheduler()
    local tick  = os.startTimer(0.5)
    local watch = os.startTimer(1.0)

    log:info("Starting scheduler.")
    while true do
        local event = { os.pullEventRaw() }
        local kind = event[1]

        if kind == "timer" and event[2] == tick then
            tick = os.startTimer(0.5)
        elseif kind == "timer" and event[2] == watch then
            if state.connected and os.epoch("utc") - state.last_rx > 2000 then
                state.connected = false
                log:warn("Link lost. Probing...")
            end
            if not state.connected then
                fc:send(proto.HELLO, {}) -- probe; ACK handled below
            end
            watch = os.startTimer(1.0)
        elseif kind == "rednet_message" then
            local id, msg = event[2], event[3]
            if id == cfg.fc_id and type(msg) == "table" then -- sender filter
                state.last_rx = os.epoch("utc")
                if not state.connected then
                    state.connected = true
                    log:info("Reconnected to FC.")
                end

                if msg.t == proto.TELEMETRY then
                    state.telemetry = msg
                elseif msg.t == proto.ALERT then
                    log:warn("FC: " .. tostring(msg.msg))
                elseif msg.t == proto.CONFIG then
                    state.config = msg.params
                end
            end
            -- anything not from the FC is ignored
        elseif kind == "monitor_touch" then
            -- local side, x, y = event[2], event[3], event[4]
            -- if side == cfg.peripherals.mon_main then
            --     mon_main:touch(x, y)
            -- end
        elseif kind == "mouse_click" then
            log:on_click(event[3], event[4], "term")
        elseif kind == "mouse_scroll" then
            log:on_scroll(event[2], term.current(), "term")
        elseif kind == "key" then
            if event[2] == 261 then return end -- DEL terminates
        end
    end
end

-- ==================================================
--
-- Run
--
-- ==================================================
local ok, err = pcall(function()
    parallel.waitForAny(init, term_renderer)
    parallel.waitForAny(scheduler, input_sender, term_renderer, function() slate:start() end, hud_parser)
end)

log:info("Stopping...")
settings.save()
log:info("Settings saved")

-- clear (blank) every non-terminal display on exit
for _, t in ipairs(renderTargets) do
    if t.target and t.key ~= "term" then
        t.target.setBackgroundColor(colors.black)
        t.target.setTextColor(colors.white)
        t.target.clear()
        t.target.setCursorPos(1, 1)
    end
end
log:info("Monitors cleared")

if ok or err == "Terminated" then
    log:error("Terminated")
else
    log:error("crash: " .. err)
end

-- land the terminal at the bottom so the shell prompt sits below the last line
log:jump("term")
local rows = log:redraw(term.current(), "term")
local _, h = term.getSize()
if #rows >= h then term.scroll(1) end
term.setCursorPos(1, h)
term.setTextColor(colors.white)
