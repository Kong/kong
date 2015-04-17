-- lapp.lua
-- Simple command-line parsing using human-readable specification
-----------------------------
--~ -- args.lua
--~ local args = require ('lapp') [[
--~ Testing parameter handling
--~     -p               Plain flag (defaults to false)
--~     -q,--quiet       Plain flag with GNU-style optional long name
--~     -o  (string)     Required string option
--~     -n  (number)     Required number option
--~     -s (default 1.0) Option that takes a number, but will default
--~     <start> (number) Required number argument
--~     <input> (default stdin)  A parameter which is an input file
--~     <output> (default stdout) One that is an output file
--~ ]]
--~ for k,v in pairs(args) do
--~     print(k,v)
--~ end
-------------------------------
--~ > args -pq -o help -n 2 2.3
--~ input   file (781C1B78)
--~ p       true
--~ s       1
--~ output  file (781C1B98)
--~ quiet   true
--~ start   2.3
--~ o       help
--~ n       2
--------------------------------

lapp = {}

local append = table.insert
local usage
local open_files = {}
local parms = {}
local aliases = {}
local parmlist = {}

local filetypes = {
    stdin = {io.stdin,'file-in'}, stdout = {io.stdout,'file-out'},
    stderr = {io.stderr,'file-out'}
}

local function quit(msg,no_usage)
    if msg then
        io.stderr:write(msg..'\n\n')
    end
    if not no_usage then
        io.stderr:write(usage)
    end
    os.exit(1);
end

local function error(msg,no_usage)
    quit(arg[0]:gsub('.+[\\/]','')..':'..msg,no_usage)
end

local function ltrim(line)
    return line:gsub('^%s*','')
end

local function rtrim(line)
    return line:gsub('%s*$','')
end

local function trim(s)
    return ltrim(rtrim(s))
end

local function open (file,opt)
    local val,err = io.open(file,opt)
    if not val then error(err,true) end
    append(open_files,val)
    return val
end

local function xassert(condn,msg)
    if not condn then
        error(msg)
    end
end

local function range_check(x,min,max,parm)
    xassert(min <= x and max >= x,parm..' out of range')
end

local function xtonumber(s)
    local val = tonumber(s)
    if not val then error("unable to convert to number: "..s) end
    return val
end

local function is_filetype(type)
    return type == 'file-in' or type == 'file-out'
end

local types = {}

local function convert_parameter(ps,val)
    if ps.converter then
        val = ps.converter(val)
    end
    if ps.type == 'number' then
        val = xtonumber(val)
    elseif is_filetype(ps.type) then
        val = open(val,(ps.type == 'file-in' and 'r') or 'w' )
    elseif ps.type == 'boolean' then
        val = true
    end
    if ps.constraint then
        ps.constraint(val)
    end
    return val
end

function lapp.add_type (name,converter,constraint)
    types[name] = {converter=converter,constraint=constraint}
end

local function force_short(short)
    xassert(#short==1,short..": short parameters should be one character")
end

local function process_options_string(str)
    local res = {}
    local varargs

    local function check_varargs(s)
        local res,cnt = s:gsub('%.%.%.$','')
        varargs = cnt > 0
        return res
    end

    local function set_result(ps,parm,val)
        if not ps.varargs then
            res[parm] = val
        else
            if not res[parm] then
                res[parm] = { val }
            else
                append(res[parm],val)
            end
        end
    end

    usage = str

    for line in str:gfind('([^\n]*)\n') do
        local optspec,optparm,i1,i2,defval,vtype,constraint
        line = ltrim(line)
        -- flags: either -<short> or -<short>,<long>
        i1,i2,optspec = line:find('^%-(%S+)')
        if i1 then
            optspec = check_varargs(optspec)
            local short,long = optspec:match('([^,]+),(.+)')
            if short then
                optparm = long:sub(3)
                aliases[short] = optparm
                force_short(short)
            else
                optparm = optspec
                force_short(optparm)
            end
        else -- is it <parameter_name>?
            i1,i2,optparm = line:find('(%b<>)')
            if i1 then
                -- so <input file...> becomes input_file ...
                optparm = check_varargs(optparm:sub(2,-2)):gsub('%A','_')
                append(parmlist,optparm)
            end
        end
        if i1 then -- this is not a pure doc line
            local last_i2 = i2
            local sval
            line = ltrim(line:sub(i2+1))
            -- do we have (default <val>) or (<type>)?
            i1,i2,typespec = line:find('^%s*(%b())')
            if i1 then
                typespec = trim(typespec:sub(2,-2)) -- trim the parens and any space
                sval = typespec:match('default%s+(.+)')
                if sval then
                    local val = tonumber(sval)
                    if val then -- we have a number!
                        defval = val
                        vtype = 'number'
                    elseif filetypes[sval] then
                        local ft = filetypes[sval]
                        defval = ft[1]
                        vtype = ft[2]
                    else
                        defval = sval
                        vtype = 'string'
                    end
                else
                    local min,max = typespec:match '([^%.]+)%.%.(.+)'
                    if min then -- it's (min..max)
                        vtype = 'number'
                        min = xtonumber(min)
                        max = xtonumber(max)
                        constraint = function(x)
                            range_check(x,min,max,optparm)
                        end
                    else -- () just contains type of required parameter
                        vtype = typespec
                    end
                end
            else -- must be a plain flag, no extra parameter required
                defval = false
                vtype = 'boolean'
            end
            local ps = {
                type = vtype,
                defval = defval,
                required = defval == nil,
                comment = line:sub((i2 or last_i2)+1) or optparm,
                constraint = constraint,
                varargs = varargs
            }
            if types[vtype] then
                local converter = types[vtype].converter
                if type(converter) == 'string' then
                    ps.type = converter
                else
                    ps.converter = converter
                end
                ps.constraint = types[vtype].constraint
            end
            parms[optparm] = ps
        end
    end
    -- cool, we have our parms, let's parse the command line args
    local iparm = 1
    local iextra = 1
    local i = 1
    local parm,ps,val
    while i <= #arg do
        -- look for a flag, -<short flags> or --<long flag>
        local i1,_,dash,parmstr = arg[i]:find('^(%-+)(%a.*)')
        if i1 then -- we have a flag
            if #dash == 2 then -- long option
                parm = parmstr
            else -- short option
                if #parmstr == 1 then
                    parm = parmstr
                else -- multiple flags after a '-',?
                    parm = parmstr:sub(1,1)
                    if parmstr:find('^%a%d+') then
                        -- a short option followed by a digit? (exception for AW ;))
                        -- push ahead into the arg array
                        table.insert(arg,i+1,parmstr:sub(2))
                    else
                        -- push multiple flags into the arg array!
                        for k = 2,#parmstr do
                            table.insert(arg,i+k-1,'-'..parmstr:sub(k,k))
                        end
                    end
                end
            end
            if parm == 'h' or parm == 'help' then
                quit()
            end
            if aliases[parm] then parm = aliases[parm] end
            ps = parms[parm]
            if not ps then error("unrecognized parameter: "..parm) end
            if ps.type ~= 'boolean' then -- we need a value! This should follow
                val = arg[i+1]
                i = i + 1
                xassert(val,parm.." was expecting a value")
            end
        else -- a parameter
            parm = parmlist[iparm]
            if not parm then
               -- extra unnamed parameters are indexed starting at 1
               parm = iextra
               iextra = iextra + 1
               ps = { type = 'string' }
            else
                ps = parms[parm]
            end
            if not ps.varargs then
                iparm = iparm + 1
            end
            val = arg[i]
        end
        ps.used = true
        val = convert_parameter(ps,val)
        set_result(ps,parm,val)
        if is_filetype(ps.type) then
            set_result(ps,parm..'_name',arg[i])
        end
        if lapp.callback then
            lapp.callback(parm,arg[i],res)
        end
        i = i + 1
    end
    -- check unused parms, set defaults and check if any required parameters were missed
    for parm,ps in pairs(parms) do
        if not ps.used then
            if ps.required then error("missing required parameter: "..parm) end
            set_result(ps,parm,ps.defval)
        end
    end
    return res
end

setmetatable(lapp, {
    __call = function(tbl,str) return process_options_string(str) end,
    __index = {
        open = open,
        quit = quit,
        error = error,
        assert = xassert,
    }
})

return lapp
