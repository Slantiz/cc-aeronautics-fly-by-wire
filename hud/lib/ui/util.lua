local util = {}

-- Rotate point (px, py) around center (cx, cy).
-- cosR/sinR are pre-computed so callers can reuse them across many points.
-- Uses screen-space convention (y increases downward).
---@param px number  @param py number
---@param cx number  @param cy number
---@param cosR number  @param sinR number
---@return number, number
function util.rotateAround(px, py, cx, cy, cosR, sinR)
    local dx, dy = px - cx, py - cy
    return cx + dx * cosR - dy * sinR,
           cy + dx * sinR + dy * cosR
end

local SUFFIXES = { "", "K", "M", "B", "T" }

-- Format a number into a fixed-width string, maximising significant digits.
-- The sign is dropped (callers encode negativity by other means, e.g. colour),
-- and the decimal point is dropped — instead a parallel mask marks which chars
-- are fractional/compressed ("D" = dim) versus integer/significant ("B" = bright).
-- Large magnitudes use K/M/B/T suffixes (e.g. 1200 -> "12K" with the "2" dim).
--
-- allowDecimals controls only the un-suffixed range: when false, values below
-- the first suffix threshold print as plain integers (e.g. 80 -> "80 "); when
-- true they fill the width with fractional digits (e.g. 80 -> "800" = 80.0).
-- Suffixed values always show fractional digits, since that is the whole point.
---@param value number
---@param width number
---@param allowDecimals boolean
---@return string text  exactly `width` characters, left-aligned
---@return string mask  same length; "B" = bright, "D" = dim
function util.formatCompact(value, width, allowDecimals)
    local av = math.abs(value)

    -- pick the smallest suffix whose integer part fits the digit budget
    local si = 1
    while si < #SUFFIXES do
        if #string.format("%.0f", math.floor(av)) <= width - #SUFFIXES[si] then break end
        av = av / 1000
        si = si + 1
    end
    local suffix = SUFFIXES[si]
    local budget = width - #suffix

    local intPart = math.floor(av)
    local fb = budget - #string.format("%.0f", intPart)
    if fb < 0 then fb = 0 end
    if suffix == "" and not allowDecimals then fb = 0 end

    local fracStr = ""
    if fb > 0 then
        local pow     = 10 ^ fb
        local fracVal = math.floor((av - intPart) * pow + 0.5)
        if fracVal >= pow then          -- rounding carried into the integer part
            intPart = intPart + 1
            fb = budget - #string.format("%.0f", intPart)
            if fb < 0 then fb = 0 end
            fracVal = 0
        end
        if fb > 0 then
            fracStr = string.format("%0" .. fb .. "d", fracVal)
        end
    end

    local intStr = string.format("%.0f", intPart)
    local digits = (intStr .. fracStr):sub(1, budget)
    local text   = digits .. suffix
    local mask   = (string.rep("B", #intStr) .. string.rep("D", #fracStr)
                    .. string.rep("B", #suffix)):sub(1, #text)

    if #text < width then
        local pad = width - #text
        text = text .. string.rep(" ", pad)
        mask = mask .. string.rep("B", pad)
    end
    return text, mask
end

return util
