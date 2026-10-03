local util = {}

-- ==================================================
-- Math
-- ==================================================

function util.clamp(num, low, high)
    num = math.min(num, high)
    num = math.max(num, low)
    return num
end

function util.remap(val, in_min, in_max, out_min, out_max)
    return out_min + (val - in_min) / (in_max - in_min) * (out_max - out_min)
end

-- ==================================================
-- Scrollable Logging (Per-Target Scroll State)
-- ==================================================

local PREFIX = #"[00:00:00] "

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
        c = { rows = {}, done = 0 }
        self._cache[w] = c
    end
    if c.done > #self.history then
        c.rows, c.done = {}, 0
    end
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

function Log:attach(key, target, live)
    local st = tstate(self, key, live)
    st.target = target
    if live ~= nil then st.live = live end
    self.dirty = true
    return st
end

local function emit(self, s, color)
    local text = tostring(s)
    self.history[#self.history + 1] = { time = os.date("%H:%M:%S"), text = text, color = color }
    for _, st in pairs(self._t) do
        -- hold scrolled-up views in place: bump by THIS view's wrapped row count
        if not st.live and st.scroll > 0 and st.width then st.scroll = st.scroll + #wrap_entry(text, st.width) end
    end
    self.dirty = true
end

function Log:info(s) emit(self, s, colors.white) end

function Log:warn(s) emit(self, s, colors.yellow) end

function Log:error(s) emit(self, s, colors.red) end

-- target: display; key: per-target id; live: pin to bottom (never scrolls)
function Log:redraw(target, key, live)
    key = key or "term"
    local st = tstate(self, key, live)
    target = target or st.target or term.current()
    st.target = target
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

function Log:redraw_all()
    for key, st in pairs(self._t) do
        if st.target then self:redraw(st.target, key) end
    end
    self.dirty = false
end

function Log:clear(key)
    local st = self._t[key]
    if not (st and st.target) then return end
    local t = st.target
    t.setBackgroundColor(colors.black)
    t.setTextColor(colors.white)
    t.clear()
    t.setCursorPos(1, 1)
end

function Log:clear_all(except)
    for key in pairs(self._t) do
        if key ~= except then self:clear(key) end
    end
end

-- Terminal-to-shell handoff
function Log:settle(key)
    key = key or "term"
    self:jump(key)
    local st = self._t[key]
    local target = (st and st.target) or term.current()
    local rows = self:redraw(target, key)
    local _, h = target.getSize()
    if #rows >= h then target.scroll(1) end
    target.setCursorPos(1, h)
    target.setTextColor(colors.white)
    return rows
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
        st.scroll = 0
        self.dirty = true
    end
end

-- Write the full log history to a file
function Log:save(path, append)
    self:info("Saving log...")
    local file, err = fs.open(path, append and "a" or "w")
    if not file then
        self:error(("Failed to open log file: %s"):format(err or path))
        return false
    end

    if not append then
        file.writeLine(("-- Log created %s, saved %s"):format(self.created, os.date("%Y-%m-%d %H:%M:%S")))
    end

    for _, e in ipairs(self.history) do
        file.writeLine(("[%s] %s"):format(e.time, e.text))
    end

    file.close()
    return true
end

-- ==================================================
-- Redstone Signals Class
-- ==================================================

local Signal = {}
Signal.__index = Signal

function Signal.new(relay, side, analog)
    return setmetatable({
        relay = relay,
        side = side,
        analog = analog,
        _desired = analog and 0 or false,
        _last = nil,
        _pulse_ticks = 0,
    }, Signal)
end

util.Signal = Signal

-- Instant setter — no peripheral write
function Signal:set(v) self._desired = v end

-- Queues a pulse; apply() will hold it high for `ticks` ticks then drop it
function Signal:pulse(ticks)
    self._desired = self.analog and 15 or true
    self._pulse_ticks = ticks or 1
end

-- Blocking — call from ticker only
function Signal:tick()
    if self._pulse_ticks > 0 then
        self._pulse_ticks = self._pulse_ticks - 1
        if self._pulse_ticks == 0 then self._desired = self.analog and 0 or false end
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
function Signal:get() return self._desired end

-- ==================================================
-- Peripherals
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

return util
