local util = {}

-- Subpixel character constants (CC's custom font, similar to Braille — 2x3 dot grid per cell)
-- Each char = string.char(128 + bitmask) where bits map to:
--   [0][1]
--   [2][3]
--   [4][5]
local C = {
    EMPTY     = string.char(128),      -- [  ][  ] all off
    FULL      = string.char(191),      -- [██][██] all on
    TOP       = string.char(128 + 3),  -- [██][  ] top row
    MID       = string.char(128 + 12), -- [  ][██][  ] middle row
    BOT       = string.char(128 + 48), -- [  ][██] bottom row
    LEFT      = string.char(128 + 21), -- [█ ][█ ][█ ] left col
    RIGHT     = string.char(128 + 42), -- [ █][ █][ █] right col
    TOP_LEFT  = string.char(128 + 1),  -- [█ ][  ][  ] single dot top-left
    TOP_RIGHT = string.char(128 + 2),  -- [ █][  ][  ] single dot top-right
    MID_LEFT  = string.char(128 + 4),  -- [  ][█ ][  ] single dot mid-left
    MID_RIGHT = string.char(128 + 8),  -- [  ][ █][  ] single dot mid-right
    BOT_LEFT  = string.char(128 + 16), -- [  ][  ][█ ] single dot bot-left
    BOT_RIGHT = string.char(128 + 32), -- [  ][  ][ █] single dot bot-right
    TOP_HALF  = string.char(128 + 15), -- [██][██][  ] top two rows
    BOT_HALF  = string.char(128 + 60), -- [  ][██][██] bottom two rows
    LEFT_TOP  = string.char(128 + 7),  -- [██][█ ][  ] top-left triangle-ish
    RIGHT_TOP = string.char(128 + 11), -- [██][ █][  ] top-right triangle-ish
}
util.C = C

-- Write text at position with optional colors
function util.write_at(mon, x, y, text, fg, bg)
    if fg then mon.setTextColor(fg) end
    if bg then mon.setBackgroundColor(bg) end
    mon.setCursorPos(x, y)
    mon.write(text)
end

-- Draw a box using half-block characters for a crisp border
function util.draw_box(mon, x1, y1, x2, y2, border_color, bg_color)
    mon.setTextColor(border_color)
    mon.setBackgroundColor(bg_color)

    -- Fill interior
    for y = y1, y2 do
        mon.setCursorPos(x1, y)
        mon.write(string.rep(" ", x2 - x1 + 1))
    end

    -- Top/bottom use subpixel top-row-full bitmask = bits 0+1 = 3, bottom-row = bits 4+5 = 48
    local top_char   = string.char(128 + 3)  -- top two subpixels on
    local bot_char   = string.char(128 + 48) -- bottom two subpixels on
    local left_char  = string.char(128 + 21) -- left column on: bits 0,2,4 = 1+4+16
    local right_char = string.char(128 + 42) -- right column on: bits 1,3,5 = 2+8+32

    mon.setCursorPos(x1, y1)
    mon.write(string.rep(top_char, x2 - x1 + 1))

    mon.setCursorPos(x1, y2)
    mon.write(string.rep(bot_char, x2 - x1 + 1))

    for y = y1 + 1, y2 - 1 do
        mon.setCursorPos(x1, y)
        mon.write(left_char)
        mon.setCursorPos(x2, y)
        mon.write(right_char)
    end
end

-- Horizontal fill bar
function util.draw_hbar(mon, x, y, width, value, max, fg, bg)
    local fill = math.floor((value / max) * width + 0.5)
    fill = math.max(0, math.min(width, fill))
    mon.setTextColor(fg)
    mon.setBackgroundColor(bg)
    mon.setCursorPos(x, y)
    mon.write(string.rep(string.char(128 + 63), fill) .. string.rep(" ", width - fill))
end

-- Vertical fill bar
function util.draw_vbar(mon, x, y, height, value, max, fg, bg)
    local fill = math.floor((value / max) * height + 0.5)
    fill = math.max(0, math.min(height, fill))
    local full_char = string.char(128 + 63)
    for row = 0, height - 1 do
        mon.setCursorPos(x, y + (height - 1 - row))
        mon.setTextColor(fg)
        mon.setBackgroundColor(bg)
        if row < fill then
            mon.write(full_char)
        else
            mon.write(" ")
        end
    end
end

-- Write text centered within a region (ox = left edge, width = region width)
function util.write_centered(mon, ox, y, width, text, fg, bg)
    local x = ox + math.floor((width - #text) / 2)
    util.write_at(mon, x, y, text, fg, bg)
end

-- Write text right-aligned within a region
function util.write_right(mon, ox, y, width, text, fg, bg)
    util.write_at(mon, ox + width - #text, y, text, fg, bg)
end

-- Draw a horizontal line
function util.draw_hline(mon, x1, x2, y, char, fg, bg)
    util.write_at(mon, x1, y, string.rep(char, x2 - x1 + 1), fg, bg)
end

-- Draw a line using Bresenham's algorithm
function util.draw_line(mon, x1, y1, x2, y2, char, fg, bg)
    if fg then mon.setTextColor(fg) end
    if bg then mon.setBackgroundColor(bg) end

    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy

    local x, y = x1, y1
    while true do
        mon.setCursorPos(x, y)
        mon.write(char)
        if x == x2 and y == y2 then break end
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy; x = x + sx
        end
        if e2 < dx then
            err = err + dx; y = y + sy
        end
    end
end

-- Draw a roll indicator line centered at cx, cy with half-length and angle in radians
function util.draw_roll_line(mon, cx, cy, half_len, angle_rad, fg, bg)
    local cos_a = math.cos(angle_rad)
    local sin_a = math.sin(angle_rad)
    local x1 = math.floor(cx - cos_a * half_len + 0.5)
    local y1 = math.floor(cy - sin_a * half_len * 0.5 + 0.5)
    local x2 = math.floor(cx + cos_a * half_len + 0.5)
    local y2 = math.floor(cy + sin_a * half_len * 0.5 + 0.5)

    local slope = math.abs(angle_rad % math.pi)
    local char
    if slope < 0.2 or slope > math.pi - 0.2 then
        char = "-"
    elseif angle_rad > 0 then
        char = "\\"
    else
        char = "/"
    end

    util.draw_line(mon, x1, y1, x2, y2, char, fg, bg)
end

-- ─────────────────────────────────────────
-- Subpixel buffer (2x3 per character cell)
-- ─────────────────────────────────────────
-- Each cell encodes a 2-wide x 3-tall pixel grid:
--   bit 0 (1)  | bit 1 (2)
--   bit 2 (4)  | bit 3 (8)
--   bit 4 (16) | bit 5 (32)
-- char = string.char(128 + bitmask)
-- "on" pixels = fg color, "off" pixels = bg color

---@class SubpixelBuffer
local SubpixelBuffer = {}
SubpixelBuffer.__index = SubpixelBuffer

-- width/height in subpixels
function SubpixelBuffer.new(width, height)
    local instance = setmetatable({}, SubpixelBuffer)
    instance.sw = width
    instance.sh = height
    instance.cw = math.ceil(width / 2)  -- char columns
    instance.ch = math.ceil(height / 3) -- char rows
    instance.pixels = {}
    instance.fg = {}                    -- per character cell foreground color
    instance.bg = {}                    -- per character cell background color
    for i = 1, instance.cw * instance.ch do
        instance.pixels[i] = 0
        instance.fg[i] = colors.white
        instance.bg[i] = colors.black
    end
    return instance
end

function SubpixelBuffer:_idx(cx, cy)
    return (cy - 1) * self.cw + cx
end

-- Set a subpixel at subpixel coords (1-based), with fg color for "on" pixels
function SubpixelBuffer:set(px, py, on, fg_color)
    local cx = math.ceil(px / 2)
    local cy = math.ceil(py / 3)
    local bit_x = (px - 1) % 2    -- 0 or 1
    local bit_y = (py - 1) % 3    -- 0, 1, or 2
    local bit = bit_y * 2 + bit_x -- 0..5
    local idx = self:_idx(cx, cy)
    if on then
        self.pixels[idx] = self.pixels[idx] + (self.pixels[idx] % (2 ^ (bit + 1)) >= 2 ^ bit and 0 or 2 ^ bit)
        if fg_color then self.fg[idx] = fg_color end
    else
        self.pixels[idx] = self.pixels[idx] - (self.pixels[idx] % (2 ^ (bit + 1)) >= 2 ^ bit and 2 ^ bit or 0)
    end
end

function SubpixelBuffer:clear(bg_color)
    for i = 1, self.cw * self.ch do
        self.pixels[i] = 0
        self.bg[i] = bg_color or colors.black
    end
end

-- Render the buffer to the monitor at character position (ox, oy)
function SubpixelBuffer:render(mon, ox, oy)
    for cy = 1, self.ch do
        for cx = 1, self.cw do
            local idx = self:_idx(cx, cy)
            local bitmask = self.pixels[idx]
            local char = bitmask == 0 and " " or string.char(128 + bitmask)
            mon.setTextColor(self.fg[idx])
            mon.setBackgroundColor(self.bg[idx])
            mon.setCursorPos(ox + cx - 1, oy + cy - 1)
            mon.write(char)
        end
    end
end

util.SubpixelBuffer = SubpixelBuffer

-- ==================================================
-- Button
-- ==================================================

local Button = {}
Button.__index = Button

function Button.new(label, x, y, width, callback)
    return setmetatable({
        label    = label,
        x        = x,
        y        = y,
        width    = width,
        callback = callback,
    }, Button)
end

function Button:draw(mon, ox, oy, fg, bg)
    local inner = string.format("%-" .. (self.width - 2) .. "s", self.label)
    util.write_at(mon, ox + self.x - 1, oy + self.y - 1, "[" .. inner .. "]", fg or colors.white, bg or colors.gray)
end

util.Button = Button

return util
