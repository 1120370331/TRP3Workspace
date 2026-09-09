-- Shared primitives. This module is bundled; no runtime require or file access.
return function(E, G)
    local error, pcall, setmetatable = G.error, G.pcall, G.setmetatable
    local floor, huge = math.floor, math.huge
    E.VERSION, E.API_VERSION = "0.5.0", 1
    E.util = {}
    function E.util.clamp(x, low, high) return math.max(low, math.min(high, x)) end
    function E.util.copy(value, depth)
        if type(value) ~= "table" then return value end
        if E.JSON and value==E.JSON.null then return value end
        if (depth or 0) > 32 then error("table depth exceeded") end
        local out = {}
        for k, v in pairs(value) do out[k] = E.util.copy(v, (depth or 0) + 1) end
        return out
    end
    function E.util.count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
    function E.util.finite(n) return type(n) == "number" and n == n and n ~= huge and n ~= -huge end
    function E.util.call(fn, ...)
        if type(fn) ~= "function" then return false, "unsupported" end
        return pcall(fn, ...)
    end
    function E.newScope()
        local self = { closed = false, disposers = {} }
        function self.add(fn)
            if self.closed then pcall(fn); return fn end
            self.disposers[#self.disposers + 1] = fn; return fn
        end
        function self.dispose()
            if self.closed then return end
            self.closed = true
            for i = #self.disposers, 1, -1 do pcall(self.disposers[i]) end
            self.disposers = {}
        end
        return self
    end
    function E.newEvents(onError)
        local listeners, queue, closed = {}, {}, false
        local self = {}
        function self.on(name, fn)
            local slot = { fn = fn, live = true }
            listeners[name] = listeners[name] or {}
            listeners[name][#listeners[name] + 1] = slot
            return function() slot.live = false end
        end
        function self.emit(name, data)
            if closed then return end
            if #queue >= 4096 then error("event queue budget exceeded") end
            queue[#queue + 1] = { name, data }
        end
        function self.flush()
            -- Newly emitted events are next-stage work, not recursive delivery.
            local current = queue; queue = {}
            for i = 1, #current do
                if closed then break end
                local slots = listeners[current[i][1]] or {}
                local limit = #slots
                for j = 1, limit do
                    if closed then break end
                    if slots[j].live then
                        local ok, err = pcall(slots[j].fn, current[i][2])
                        if not ok then onError(err); return end
                    end
                end
            end
        end
        function self.close() closed = true; queue = {}; listeners = {} end
        return self
    end

    local JSON = { null = {} }; E.JSON = JSON
    local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    local function quote(s)
        return '"' .. s:gsub('[%z\1-\31\\"]', function(c) return escapes[c] or string.format('\\u%04x', string.byte(c)) end) .. '"'
    end
    function JSON.encode(value)
        local seen, nodes = {}, 0
        local function encode(v, depth)
            nodes = nodes + 1
            if depth > 32 or nodes > 80000 then error("JSON structure budget exceeded") end
            if v == JSON.null or v == nil then return "null" end
            local kind = type(v)
            if kind == "boolean" then return v and "true" or "false" end
            if kind == "number" then
                if not E.util.finite(v) then error("JSON non-finite number") end
                return string.format("%.17g", v)
            end
            if kind == "string" then return quote(v) end
            if kind ~= "table" or seen[v] then error("JSON unsupported/cyclic value") end
            seen[v] = true
            local array, count, max = true, 0, 0
            for k in pairs(v) do
                count = count + 1
                if type(k) ~= "number" or k < 1 or k ~= floor(k) then array = false else max = math.max(max, k) end
            end
            array = array and count > 0 and max == count
            local out = {}
            if array then
                for i = 1, count do out[i] = encode(v[i], depth + 1) end
            else
                local keys = {}
                for k in pairs(v) do if type(k) ~= "string" then error("JSON object keys must be strings") end; keys[#keys + 1] = k end
                table.sort(keys)
                for i = 1, #keys do out[i] = quote(keys[i]) .. ":" .. encode(v[keys[i]], depth + 1) end
            end
            seen[v] = nil
            return (array and "[" or "{") .. table.concat(out, ",") .. (array and "]" or "}")
        end
        return encode(value, 0)
    end
    local function utf8(n)
        if n < 128 then return string.char(n) end
        if n < 2048 then return string.char(192 + floor(n / 64), 128 + n % 64) end
        if n < 65536 then return string.char(224 + floor(n / 4096), 128 + floor(n / 64) % 64, 128 + n % 64) end
        return string.char(240 + floor(n / 262144), 128 + floor(n / 4096) % 64, 128 + floor(n / 64) % 64, 128 + n % 64)
    end
    function JSON.decode(text, maxBytes)
        if type(text) ~= "string" or #text > (maxBytes or 524288) then error("JSON input budget exceeded") end
        local pos, nodes = 1, 0
        local function skip() local _, finish = text:find("^[ \t\r\n]*", pos); pos = (finish or pos - 1) + 1 end
        local function stringValue()
            pos = pos + 1; local out = {}
            while pos <= #text do
                local c = text:sub(pos, pos); pos = pos + 1
                if c == '"' then return table.concat(out) end
                if c == "\\" then
                    local e = text:sub(pos, pos); pos = pos + 1
                    local map = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
                    if map[e] then out[#out + 1] = map[e]
                    elseif e == "u" then
                        local hex = text:sub(pos, pos + 3)
                        if not hex:match("^%x%x%x%x$") then error("bad unicode escape") end
                        local n = tonumber(hex, 16); pos = pos + 4
                        if n >= 55296 and n <= 56319 then
                            local low = text:sub(pos + 2, pos + 5)
                            if text:sub(pos, pos + 1) ~= "\\u" or not low:match("^%x%x%x%x$") then error("bad surrogate") end
                            local m = tonumber(low, 16)
                            if m < 56320 or m > 57343 then error("bad surrogate") end
                            pos = pos + 6; n = 65536 + (n - 55296) * 1024 + m - 56320
                        elseif n >= 56320 and n <= 57343 then error("unpaired surrogate") end
                        out[#out + 1] = utf8(n)
                    else error("bad string escape") end
                else
                    if string.byte(c) < 32 then error("control byte in JSON string") end
                    out[#out + 1] = c
                end
            end
            error("unterminated string")
        end
        local parse
        parse = function(depth)
            nodes = nodes + 1
            if depth > 32 or nodes > 80000 then error("JSON structure budget exceeded") end
            skip(); local c = text:sub(pos, pos)
            if c == '"' then return stringValue() end
            if c == "{" or c == "[" then
                local object, result, index = c == "{", {}, 1
                local close = object and "}" or "]"; pos = pos + 1; skip()
                if text:sub(pos, pos) == close then pos = pos + 1; return result end
                while true do
                    local key = index
                    if object then
                        skip(); if text:sub(pos, pos) ~= '"' then error("object key expected") end
                        key = stringValue(); skip()
                        if result[key] ~= nil then error("duplicate JSON key") end
                        if text:sub(pos, pos) ~= ":" then error("colon expected") end; pos = pos + 1
                    end
                    result[key] = parse(depth + 1); index = index + 1; skip()
                    c = text:sub(pos, pos); pos = pos + 1
                    if c == close then return result end
                    if c ~= "," then error("separator expected") end
                end
            end
            for _, pair in ipairs({ {"true", true}, {"false", false}, {"null", JSON.null} }) do
                if text:sub(pos, pos + #pair[1] - 1) == pair[1] then pos = pos + #pair[1]; return pair[2] end
            end
            local start = pos
            if c == "-" then pos = pos + 1 end
            local first = text:sub(pos, pos)
            if not first:match("%d") then error("value expected at " .. tostring(pos)) end
            if first == "0" then pos = pos + 1 else while text:sub(pos, pos):match("%d") do pos = pos + 1 end end
            if text:sub(pos, pos) == "." then
                pos = pos + 1
                if not text:sub(pos, pos):match("%d") then error("fraction expected") end
                while text:sub(pos, pos):match("%d") do pos = pos + 1 end
            end
            if text:sub(pos, pos):match("[eE]") then
                pos = pos + 1
                if text:sub(pos, pos):match("[+-]") then pos = pos + 1 end
                if not text:sub(pos, pos):match("%d") then error("exponent expected") end
                while text:sub(pos, pos):match("%d") do pos = pos + 1 end
            end
            local n = tonumber(text:sub(start, pos - 1))
            if not E.util.finite(n) then error("invalid JSON number") end
            return n
        end
        local result = parse(0); skip()
        if pos <= #text then error("trailing JSON data") end
        return result
    end
end
