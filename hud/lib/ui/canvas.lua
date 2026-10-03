local Element = require("lib.ui.element")

---@class Canvas : Element
---@field bgColor number
---@field buffer table
---@field priority table
local Canvas = setmetatable({}, Element)
Canvas.__index = Canvas

---@param x number
---@param y number
---@param w number
---@param h number
---@param bgColor? number
---@return Canvas
function Canvas:new(x, y, w, h, bgColor)
    local obj = Element.new(self, x, y, w, h) --[[@as Canvas]]
    obj.bgColor = bgColor or colors.black
    local buf, pri = {}, {}
    for by = 1, h * 3 do
        buf[by] = {}
        pri[by] = {}
        for bx = 1, w * 2 do
            buf[by][bx] = obj.bgColor
            pri[by][bx] = 0
        end
    end
    obj.buffer   = buf
    obj.priority = pri
    return obj
end

---@param bx number
---@param by number
---@param color number
---@param priority? number
function Canvas:setPixel(bx, by, color, priority)
    self.buffer[by][bx]   = color
    self.priority[by][bx] = priority or 0
end

---@param color number
function Canvas:clear(color)
    local buf, pri = self.buffer, self.priority
    for by = 1, self.h * 3 do
        local rb, rp = buf[by], pri[by]
        for bx = 1, self.w * 2 do
            rb[bx] = color
            rp[bx] = 0
        end
    end
end

---@param bx1 number
---@param by1 number
---@param bx2 number
---@param by2 number
---@param color number
function Canvas:fill(bx1, by1, bx2, by2, color)
    local bw, bh = self.w * 2, self.h * 3
    bx1 = math.max(1, bx1); by1 = math.max(1, by1)
    bx2 = math.min(bw, bx2); by2 = math.min(bh, by2)
    local buf, pri = self.buffer, self.priority
    for by = by1, by2 do
        local rb, rp = buf[by], pri[by]
        for bx = bx1, bx2 do
            rb[bx] = color
            rp[bx] = 0
        end
    end
end

---@param bx1 number
---@param by1 number
---@param bx2 number
---@param by2 number
---@param color number
---@param priority? number
function Canvas:line(bx1, by1, bx2, by2, color, priority)
    local bw, bh = self.w * 2, self.h * 3
    local pval = priority or 0
    local dx = math.abs(bx2 - bx1)
    local dy = math.abs(by2 - by1)
    local sx = bx1 < bx2 and 1 or -1
    local sy = by1 < by2 and 1 or -1
    local err = dx - dy
    local x, y = bx1, by1
    while true do
        if x >= 1 and x <= bw and y >= 1 and y <= bh then
            self.buffer[y][x]   = color
            self.priority[y][x] = pval
        end
        if x == bx2 and y == by2 then break end
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy; x = x + sx
        end
        if e2 < dx then
            err = err + dx; y = y + sy
        end
    end
end

---@param screen Screen
---@param absX number
---@param absY number
function Canvas:draw(screen, absX, absY)
    local t   = screen.target
    local buf = self.buffer
    local pri = self.priority

    for cy = 0, self.h - 1 do
        for cx = 0, self.w - 1 do
            local bx0 = cx * 2 + 1
            local by0 = cy * 3 + 1

            local pixels = {
                buf[by0][bx0], buf[by0][bx0 + 1],
                buf[by0 + 1][bx0], buf[by0 + 1][bx0 + 1],
                buf[by0 + 2][bx0], buf[by0 + 2][bx0 + 1],
            }
            local prios = {
                pri[by0][bx0], pri[by0][bx0 + 1],
                pri[by0 + 1][bx0], pri[by0 + 1][bx0 + 1],
                pri[by0 + 2][bx0], pri[by0 + 2][bx0 + 1],
            }

            t.setCursorPos(absX + cx, absY + cy)

            -- find highest priority level present in this cell
            local maxPri = 0
            for i = 1, 6 do if prios[i] > maxPri then maxPri = prios[i] end end

            if maxPri > 0 then
                -- fg = most frequent color among max-priority pixels
                local priCount = {}
                for i = 1, 6 do
                    if prios[i] == maxPri then
                        local c = pixels[i]
                        priCount[c] = (priCount[c] or 0) + 1
                    end
                end
                local fg, fgN = nil, 0
                for c, n in pairs(priCount) do if n > fgN then fg, fgN = c, n end end
                -- pattern: only max-priority pixels matching fg color
                -- everything else (lower-priority + non-fg max-priority) votes for bg
                local pattern, bitVal = 0, 1
                local bgCount = {}
                for i = 1, 6 do
                    if prios[i] == maxPri and pixels[i] == fg then
                        pattern = pattern + bitVal
                    else
                        local c = pixels[i]
                        bgCount[c] = (bgCount[c] or 0) + 1
                    end
                    bitVal = bitVal * 2
                end
                local bg, bgN = colors.black, 0
                for c, n in pairs(bgCount) do if n > bgN then bg, bgN = c, n end end
                if pattern >= 32 then
                    pattern = bit32.bxor(pattern, 63)
                    fg, bg = bg, fg
                end
                t.setBackgroundColor(bg)
                t.setTextColor(fg)
                t.write(string.char(128 + pattern))
            else
                -- no priority: majority = bg, minority = fg
                local colorCount = {}
                for _, c in ipairs(pixels) do
                    colorCount[c] = (colorCount[c] or 0) + 1
                end
                local bg, fg, bgN, fgN = nil, nil, 0, 0
                for c, n in pairs(colorCount) do
                    if n > bgN then
                        fg, fgN = bg, bgN; bg, bgN = c, n
                    elseif n > fgN then
                        fg, fgN = c, n
                    end
                end
                if not fg then
                    t.setBackgroundColor(bg)
                    t.write(" ")
                else
                    local pattern, bitVal = 0, 1
                    for _, c in ipairs(pixels) do
                        if c == fg then pattern = pattern + bitVal end
                        bitVal = bitVal * 2
                    end
                    if pattern >= 32 then
                        pattern = bit32.bxor(pattern, 63)
                        fg, bg = bg, fg
                    end
                    t.setBackgroundColor(bg)
                    t.setTextColor(fg)
                    t.write(string.char(128 + pattern))
                end
            end
        end
    end
end

return Canvas
