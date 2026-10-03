local proto = require("proto")

local Net = {}
Net.__index = Net

function Net.open(side)
    if side then
        if peripheral.getType(side) ~= "modem" then
            return false, "no modem on side '" .. tostring(side) .. "'"
        end
        rednet.open(side)
        return true
    end
    if log then log:warn("Net.open: no modem given, searching...") end
    if peripheral.find("modem", function(n)
            rednet.open(n); return true
        end) then
        return true
    end
    return false, "no modem found"
end

function Net.new(peer_id)
    return setmetatable({
        peer_id = peer_id,
        seq = 0,
    }, Net)
end

function Net:envelope(t, payload)
    self.seq = self.seq + 1
    local m = payload or {}
    m.t, m.seq, m.ts = t, self.seq, os.epoch("utc") -- ts is for latency later
    return m
end

function Net:send(t, payload)
    rednet.send(self.peer_id, self:envelope(t, payload), proto.PROTOCOL)
end

-- confirm a known id is alive and in range
function Net:wait_for(timeout)
    local deadline = os.clock() + (timeout or 5)
    repeat
        self:send(proto.HELLO, {})
        local t = os.startTimer(0.5)
        while true do
            local ev = { os.pullEvent() }
            if ev[1] == "rednet_message" and ev[2] == self.peer_id
                and type(ev[3]) == "table" and ev[3].t == proto.ACK then
                return true -- FC answered
            elseif ev[1] == "timer" and ev[2] == t then
                break       -- no reply, retry
            end
        end
    until os.clock() > deadline
    return false, "FC not responding"
end

-- ask a host for its config and block until it replies (startup phase only)
function Net:pull_config(timeout)
    self:send(proto.CONFIG_REQ, {})
    local timer = os.startTimer(timeout or 2)
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "rednet_message" and ev[2] == self.peer_id
            and type(ev[3]) == "table" and ev[3].t == proto.CONFIG then
            return ev[3].params
        elseif ev[1] == "timer" and ev[2] == timer then
            return nil, "no config reply"
        end
    end
end

return Net
