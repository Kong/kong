-- handler file for both the pre-function and post-function plugin


local config_cache do

  local env = {}

  local no_op = function() end

  local function make_read_only_table(t)
    setmetatable(t, {
      __newindex = function()
        error("This table is read-only.")
      end
    })
  end

  -- safe Lua modules and functions
  ([[
  _VERSION assert error    ipairs   next pairs
  pcall    select tonumber tostring type unpack xpcall
  coroutine.create coroutine.resume coroutine.running coroutine.status
  coroutine.wrap   coroutine.yield
  math.abs   math.acos math.asin  math.atan math.atan2 math.ceil
  math.cos   math.cosh math.deg   math.exp  math.fmod  math.floor
  math.frexp math.huge math.ldexp math.log  math.log10 math.max
  math.min   math.modf math.pi    math.pow  math.rad   math.random
  math.sin   math.sinh math.sqrt  math.tan  math.tanh
  os.clock os.difftime os.time
  string.byte string.char  string.find  string.format string.gmatch
  string.gsub string.len   string.lower string.match  string.reverse
  string.sub  string.upper
  table.insert table.maxn table.remove table.sort
  ]]):gsub('%S+', function(id)
    local module, method = id:match('([^%.]+)%.([^%.]+)')
    if module then
      env[module]         = env[module] or {}
      env[module][method] = _G[module][method]
    else
      env[id] = _G[id]
    end
  end)

  make_read_only_table(env.coroutine)
  make_read_only_table(env.math)
  make_read_only_table(env.os)
  make_read_only_table(env.string)
  make_read_only_table(env.table)


  local function make_function(func_str)
    local f = assert(loadstring(func_str, nil, "t")) -- disallow binary code

    -- make kong.* available on env
    if not env.kong then
      -- create a protected kong node
      env.kong = kong
    end

    -- make ngx available on env
    if not env.ngx then
      env.ngx = ngx
    end

    if not getmetatable(env) then
      make_read_only_table(env)
    end

    setfenv(f, env)
    return f
  end


  -- compiles the array for a phase into a single function
  local function compile_phase_array(phase_funcs)
    if not phase_funcs or #phase_funcs == 0 then
      -- nothing to do for this phase
      return no_op
    else
      -- compile the functions we got
      local compiled = {}
      for i, func_string in ipairs(phase_funcs) do
        local func = make_function(func_string)

        local first_run_complete = false
        compiled[i] = function()
          -- this is a temporary closure, that will replace itself
          if not first_run_complete then
            first_run_complete = true
            local result = func() --> this might call ngx.exit()

            -- if we ever get here, then there was NO early exit from a 0.1.0
            -- type config
            if type(result) == "function" then
              -- this is a new function (0.2.0+), with upvalues
              -- the first call to func above only initialized it, so run again
              func = result
              compiled[i] = func
              func() --> this again, may do an early exit
            end

            -- if we ever get here, then there was no early exit from either
            -- 0.1.0 or 0.2.0+ code
            -- Replace the entry of this closure in the array with the actual
            -- function, since the closure is no longer needed.
            compiled[i] = func

          else
            -- first run is marked as complete, but we (this temporary closure)
            -- are being called again. So we are here only if the initial
            -- function call did an early exit.
            -- So replace this closure now;
            compiled[i] = func
            -- And call it again, for this 2nd run;
            func()
          end
          -- unreachable
        end
      end

      -- now return a function that executes the entire array
      return function()
        for _, f in ipairs(compiled) do f() end
      end
    end
  end


  local phases = { "certificate", "rewrite", "access",
                   "header_filter", "body_filter", "log",
                   "functions" } -- <-- this one being legacy


  config_cache = setmetatable({}, {
    __mode = "k",
    __index = function(self, config)
      -- config was not found yet, so go and compile our config functions
      local runtime_funcs = {}
      for _, phase in ipairs(phases) do
        local func = compile_phase_array(config[phase])

        if phase == "functions" then
          if func == no_op then
            func = nil -- do not set a "functions" key, since we won't run it anyway
          else
            -- functions, which is legacy is specified, so inject as "access". The
            -- schema already prevents "access" and "functions" to co-exist, so
            -- this should be safe.
            phase = "access"
          end
        end

        runtime_funcs[phase] = func
      end
      -- store compiled results in cache, and return them
      self[config] = runtime_funcs
      return runtime_funcs
    end
  })
end



return function(priority)

  local ServerlessFunction = {
    PRIORITY = priority,
    VERSION = "2.0.0",
  }

  function ServerlessFunction:certificate(config)
    config_cache[config].certificate()
  end

  function ServerlessFunction:rewrite(config)
    config_cache[config].rewrite()
  end

  function ServerlessFunction:access(config)
    config_cache[config].access()
  end

  function ServerlessFunction:header_filter(config)
    config_cache[config].header_filter()
  end

  function ServerlessFunction:body_filter(config)
    config_cache[config].body_filter()
  end

  function ServerlessFunction:log(config)
    config_cache[config].log()
  end


  return ServerlessFunction
end
