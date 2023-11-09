-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local setmetatable = setmetatable
local loadstring = loadstring
local loadchunk
local tostring = tostring
local setfenv = setfenv
local require = require
local capture
local concat = table.concat
local assert = assert
local prefix
local write = io.write
local phase
local open = io.open
local load = load
local type = type
local dump = string.dump
local find = string.find
local gsub = string.gsub
local byte = string.byte
local null
local sub = string.sub
local ngx = ngx
local jit = jit
local var

local _VERSION = _VERSION
local _ENV = _ENV -- luacheck: globals _ENV
local _G = _G

local HTML_ENTITIES = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&#39;",
    ["/"] = "&#47;"
}

local CODE_ENTITIES = {
    ["{"] = "&#123;",
    ["}"] = "&#125;",
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&#39;",
    ["/"] = "&#47;"
}

local ESC    = byte("\27")
local NUL    = byte("\0")
local HT     = byte("\t")
local VT     = byte("\v")
local LF     = byte("\n")
local SOL    = byte("/")
local BSOL   = byte("\\")
local SP     = byte(" ")
local AST    = byte("*")
local NUM    = byte("#")
local LPAR   = byte("(")
local LSQB   = byte("[")
local LCUB   = byte("{")
local MINUS  = byte("-")
local PERCNT = byte("%")

local EMPTY  = ""

local VAR_PHASES

local newtab = require("table.new")

local caching = true
local template = newtab(0, 13)

template._VERSION = "2.0"
template.cache    = {}

local function enabled(val)
    if val == nil then return true end
    return val == true or (val == "1" or val == "true" or val == "on")
end

local function trim(s)
    return gsub(gsub(s, "^%s+", EMPTY), "%s+$", EMPTY)
end

local function rpos(view, s)
    while s > 0 do
        local c = byte(view, s, s)
        if c == SP or c == HT or c == VT or c == NUL then
            s = s - 1
        else
            break
        end
    end
    return s
end

local function escaped(view, s)
    if s > 1 and byte(view, s - 1, s - 1) == BSOL then
        if s > 2 and byte(view, s - 2, s - 2) == BSOL then
            return false, 1
        else
            return true, 1
        end
    end
    return false, 0
end

local function readfile(path)
    local file = open(path, "rb")
    if not file then return nil end
    local content = file:read "*a"
    file:close()
    return content
end

local function loadlua(path)
    return readfile(path) or path
end

local function loadngx(path)
    local vars = VAR_PHASES[phase()]
    local file, location = path, vars and var.template_location
    if byte(file, 1)  == SOL then file = sub(file, 2) end
    if location and location ~= EMPTY then
        if byte(location, -1) == SOL then location = sub(location, 1, -2) end
        local res = capture(concat{ location, "/", file})
        if res.status == 200 then return res.body end
    end
    local root = vars and (var.template_root or var.document_root) or prefix
    if byte(root, -1) == SOL then root = sub(root, 1, -2) end
    return readfile(concat{ root, "/", file }) or path
end

do
    if ngx then
        VAR_PHASES = {
            set           = true,
            rewrite       = true,
            access        = true,
            content       = true,
            header_filter = true,
            body_filter   = true,
            log           = true
        }
        template.print = ngx.print or write
        template.load  = loadngx
        prefix, var, capture, null, phase = ngx.config.prefix(), ngx.var, ngx.location.capture, ngx.null, ngx.get_phase
        if VAR_PHASES[phase()] then
            caching = enabled(var.template_cache)
        end
    else
        template.print = write
        template.load  = loadlua
    end
    if _VERSION == "Lua 5.1" then
        local context = { __index = function(t, k)
            return t.context[k] or t.template[k] or _G[k]
        end }
        if jit then
            loadchunk = function(view)
                return assert(load(view, nil, nil, setmetatable({ template = template }, context)))
            end
        else
            loadchunk = function(view)
                local func = assert(loadstring(view))
                setfenv(func, setmetatable({ template = template }, context))
                return func
            end
        end
    else
        local context = { __index = function(t, k)
            return t.context[k] or t.template[k] or _ENV[k]
        end }
        loadchunk = function(view)
            return assert(load(view, nil, nil, setmetatable({ template = template }, context)))
        end
    end
end

function template.eval(exp) return exp end

function template.caching(enable)
    if enable ~= nil then caching = enable == true end
    return caching
end

function template.output(s)
    if s == nil or s == null then return EMPTY end
    if type(s) == "function" then return template.output(s()) end
    return tostring(s)
end

function template.escape(s, c)
    if type(s) == "string" then
        if c then return gsub(s, "[}{\">/<'&]", CODE_ENTITIES) end
        return gsub(s, "[\">/<'&]", HTML_ENTITIES)
    end
    return template.output(s)
end

function template.new(view, layout)
    assert(view, "view was not provided for template.new(view, layout).")
    local render, compile = template.render, template.compile
    if layout then
        if type(layout) == "table" then
            return setmetatable({ render = function(self, context)
                context = context or self
                context.blocks = context.blocks or {}
                context.view = compile(view)(context)
                layout.blocks = context.blocks or {}
                layout.view = context.view or EMPTY
                return layout:render()
            end }, { __tostring = function(self)
                local context = self
                context.blocks = context.blocks or {}
                context.view = compile(view)(context)
                layout.blocks = context.blocks or {}
                layout.view = context.view
                return tostring(layout)
            end })
        else
            return setmetatable({ render = function(self, context)
                context = context or self
                context.blocks = context.blocks or {}
                context.view = compile(view)(context)
                return render(layout, context)
            end }, { __tostring = function(self)
                local context = self
                context.blocks = context.blocks or {}
                context.view = compile(view)(context)
                return compile(layout)(context)
            end })
        end
    end
    return setmetatable({ render = function(self, context)
        return render(view, context or self)
    end }, { __tostring = function(self)
        return compile(view)(self)
    end })
end

function template.precompile(view, path, strip)
    local chunk = dump(template.compile(view), strip ~= false)
    if path then
        local file = open(path, "wb")
        file:write(chunk)
        file:close()
    end
    return chunk
end

function template.compile(view, key, plain)
    assert(view, "view was not provided for template.compile(view, key, plain).")
    if key == "no-cache" then
        return loadchunk(template.parse(view, plain)), false
    end
    key = key or view
    local cache = template.cache
    if cache[key] then return cache[key], true end
    local func = loadchunk(template.parse(view, plain))
    if caching then cache[key] = func end
    return func, false
end

function template.parse(view, plain)
    assert(view, "view was not provided for template.parse(view, plain).")
    if not plain then
        view = template.load(view)
        if byte(view, 1, 1) == ESC then return view end
    end
    local j = 2
    local c = {[[
context=... or {}
local function include(v, c) return template.compile(v)(c or context) end
local ___,blocks,layout={},blocks or {}
]] }
    local i, s = 1, find(view, "{", 1, true)
    local eval = template.eval
    while s do
        local t, p = byte(view, s + 1, s + 1), s + 2
        if t == LCUB then
            local e = find(view, "}}", p, true)
            if e then
                local z, w = escaped(view, s)
                if i < s - w then
                    c[j] = "___[#___+1]=[=[\n"
                    c[j+1] = sub(view, i, s - 1 - w)
                    c[j+2] = "]=]\n"
                    j=j+3
                end
                if z then
                    i = s
                else
                  local exp = trim(sub(view, p, e - 1))
                  c[j] = "___[#___+1]=template.escape("
                  c[j+1] = eval(exp)
                  c[j+2] = ")\n"
                  j=j+3
                  s, i = e + 1, e + 2
                end
            end
        elseif t == AST then
            local e = find(view, "*}", p, true)
            if e then
                local z, w = escaped(view, s)
                if i < s - w then
                    c[j] = "___[#___+1]=[=[\n"
                    c[j+1] = sub(view, i, s - 1 - w)
                    c[j+2] = "]=]\n"
                    j=j+3
                end
                if z then
                    i = s
                else
                    local exp = trim(sub(view, p, e - 1))
                    c[j] = "___[#___+1]=template.output("
                    c[j+1] = eval(exp)
                    c[j+2] = ")\n"
                    j=j+3
                    s, i = e + 1, e + 2
                end
            end
        elseif t == PERCNT then
            local e = find(view, "%}", p, true)
            if e then
                local z, w = escaped(view, s)
                if z then
                    if i < s - w then
                        c[j] = "___[#___+1]=[=[\n"
                        c[j+1] = sub(view, i, s - 1 - w)
                        c[j+2] = "]=]\n"
                        j=j+3
                    end
                    i = s
                else
                    local n = e + 2
                    if byte(view, n, n) == LF then
                        n = n + 1
                    end
                    local r = rpos(view, s - 1)
                    if i <= r then
                        c[j] = "___[#___+1]=[=[\n"
                        c[j+1] = sub(view, i, r)
                        c[j+2] = "]=]\n"
                        j=j+3
                    end
                    c[j] = trim(sub(view, p, e - 1))
                    c[j+1] = "\n"
                    j=j+2
                    s, i = n - 1, n
                end
            end
        elseif t == LPAR then
            local e = find(view, ")}", p, true)
            if e then
                local z, w = escaped(view, s)
                if i < s - w then
                    c[j] = "___[#___+1]=[=[\n"
                    c[j+1] = sub(view, i, s - 1 - w)
                    c[j+2] = "]=]\n"
                    j=j+3
                end
                if z then
                    i = s
                else
                    local f = sub(view, p, e - 1)
                    local x = find(f, ",", 2, true)
                    if x then
                        c[j] = "___[#___+1]=include([=["
                        c[j+1] = trim(sub(f, 1, x - 1))
                        c[j+2] = "]=],"
                        c[j+3] = trim(sub(f, x + 1))
                        c[j+4] = ")\n"
                        j=j+5
                    else
                        c[j] = "___[#___+1]=include([=["
                        c[j+1] = trim(f)
                        c[j+2] = "]=])\n"
                        j=j+3
                    end
                    s, i = e + 1, e + 2
                end
            end
        elseif t == LSQB then
            local e = find(view, "]}", p, true)
            if e then
                local z, w = escaped(view, s)
                if i < s - w then
                    c[j] = "___[#___+1]=[=[\n"
                    c[j+1] = sub(view, i, s - 1 - w)
                    c[j+2] = "]=]\n"
                    j=j+3
                end
                if z then
                    i = s
                else
                    c[j] = "___[#___+1]=include("
                    c[j+1] = trim(sub(view, p, e - 1))
                    c[j+2] = ")\n"
                    j=j+3
                    s, i = e + 1, e + 2
                end
            end
        elseif t == MINUS then
            local e = find(view, "-}", p, true)
            if e then
                local x, y = find(view, sub(view, s, e + 1), e + 2, true)
                if x then
                    local z, w = escaped(view, s)
                    if z then
                        if i < s - w then
                            c[j] = "___[#___+1]=[=[\n"
                            c[j+1] = sub(view, i, s - 1 - w)
                            c[j+2] = "]=]\n"
                            j=j+3
                        end
                        i = s
                    else
                        y = y + 1
                        x = x - 1
                        if byte(view, y, y) == LF then
                            y = y + 1
                        end
                        local b = trim(sub(view, p, e - 1))
                        if b == "verbatim" or b == "raw" then
                            if i < s - w then
                                c[j] = "___[#___+1]=[=[\n"
                                c[j+1] = sub(view, i, s - 1 - w)
                                c[j+2] = "]=]\n"
                                j=j+3
                            end
                            c[j] = "___[#___+1]=[=["
                            c[j+1] = sub(view, e + 2, x)
                            c[j+2] = "]=]\n"
                            j=j+3
                        else
                            if byte(view, x, x) == LF then
                                x = x - 1
                            end
                            local r = rpos(view, s - 1)
                            if i <= r then
                                c[j] = "___[#___+1]=[=[\n"
                                c[j+1] = sub(view, i, r)
                                c[j+2] = "]=]\n"
                                j=j+3
                            end
                            c[j] = 'blocks["'
                            c[j+1] = b
                            c[j+2] = '"]=include[=['
                            c[j+3] = sub(view, e + 2, x)
                            c[j+4] = "]=]\n"
                            j=j+5
                        end
                        s, i = y - 1, y
                    end
                end
            end
        elseif t == NUM then
            local e = find(view, "#}", p, true)
            if e then
                local z, w = escaped(view, s)
                if i < s - w then
                    c[j] = "___[#___+1]=[=[\n"
                    c[j+1] = sub(view, i, s - 1 - w)
                    c[j+2] = "]=]\n"
                    j=j+3
                end
                if z then
                    i = s
                else
                    e = e + 2
                    if byte(view, e, e) == LF then
                        e = e + 1
                    end
                    s, i = e - 1, e
                end
            end
        end
        s = find(view, "{", s + 1, true)
    end
    s = sub(view, i)
    if s and s ~= EMPTY then
        c[j] = "___[#___+1]=[=[\n"
        c[j+1] = s
        c[j+2] = "]=]\n"
        j=j+3
    end
    c[j] = "return layout and include(layout,setmetatable({view=table.concat(___),blocks=blocks},{__index=context})) or table.concat(___)" -- luacheck: ignore
    return concat(c)
end

function template.render(view, context, key, plain)
    assert(view, "view was not provided for template.render(view, context, key, plain).")
    return template.print(template.compile(view, key, plain)(context))
end

return template
