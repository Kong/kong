local match    = ngx.re.match
local unpack   = table.unpack or unpack
local concat   = table.concat
local find     = string.find
local sub      = string.sub
local huge     = math.huge
local tonumber = tonumber
local unescape = ngx.unescape_uri
local cache = {}
return function(location, pattern, insensitive)
    if not cache[pattern] then
        local i, c, p, j, n = 1, {}, {}, 0, 1
        local s = find(pattern, ":", 1, true)
        while s do
            if s > i then
                p[n] = [[\Q]]
                p[n+1] = sub(pattern, i, s - 1)
                p[n+2] = [[\E]]
                n=n+3
            end
            local x = sub(pattern, s, s + 6)
            if x == ":number" then
                p[n] = [[(\d+)]]
                s, j, n = s + 7, j + 1, n + 1
                c[j] = tonumber
            elseif x == ":string" then
                p[n] = [[([^/]+)]]
                s, j, n = s + 7, j + 1, n + 1
                c[j] = unescape
            end
            i = s
            s = find(pattern, ":", s + 1, true)
        end
        if j > 0 then
            local rest = sub(pattern, i)
            if #rest > 0 then
                p[n] = [[\Q]]
                p[n+1] = rest
                p[n+2] = [[\E$]]
            else
                p[n] = "$"
            end
        else
            p[1] = pattern
            p[2] = "$"
        end
        cache[pattern] = { concat(p), j, c }
    end
    local p, j, c = unpack(cache[pattern])
    local m = match(location, p, insensitive and "aijosu" or "ajosu")
    if m then
        if m[1] then
            for i = 1, j do
                m[i] = c[i](m[i])
                if m[i] == huge then return nil end
            end
            return unpack(m)
        end
        return m[0]
    end
end
