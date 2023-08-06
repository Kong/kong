local TEMPLATE = [[
  return function(always_enabled_groups, group_name, original_func, handlers)
    return function(%s)
      if not always_enabled_groups[group_name] then
        local dynamic_hook = ngx.ctx.dynamic_hook
        if not dynamic_hook then
          return original_func(%s)
        end
  
        local enabled_groups = dynamic_hook.enabled_groups
        if not enabled_groups[group_name] then
          return original_func(%s)
        end
      end
  
      if handlers.before_mut then
        local ok
        ok, %s = pcall(handlers.before_mut, %s)
        if not ok then
          ngx.log(ngx.WARN,
                  string.format("failed to run before_mut hook of %%s: %%s",
                              group_name, a0))
        end
      end
  
      if handlers.befores then
        for _, func in ipairs(handlers.befores) do
          local ok, err = pcall(func, %s)
          if not ok then
            ngx.log(ngx.WARN,
                    string.format("failed to run before hook of %%s: %%s",
                                  group_name, err))
          end
        end
      end
      
      ngx.log(ngx.ERR, debug.traceback())
      local r0, r1, r2, r3, r4, r5, r6, r7 = original_func(%s)
  
      if handlers.after_mut then
        local ok, err = pcall(handlers.after_mut, r0, r1, r2, r3, r4, r5, r6, r7)
        if not ok then
          ngx.log(ngx.WARN,
                  string.format("failed to run after_mut hook of %%s: %%s",
                                group_name, err))
        end
      end
  
      if handlers.afters then
        for _, func in ipairs(handlers.afters) do
          local ok, err = pcall(func, r0, r1, r2, r3, r4, r5, r6, r7)
          if not ok then
            ngx.log(ngx.WARN,
                    string.format("failed to run after hook of %%s: %%s",
                                  group_name, err))
          end
        end
      end
  
      return r0, r1, r2, r3, r4, r5, r6, r7
    end
  end
]]


local _M = {}


local function warp_function_0(always_enabled_groups, group_name, original_func, handlers)
  return function()
    if not always_enabled_groups[group_name] then
      local dynamic_hook = ngx.ctx.dynamic_hook
      if not dynamic_hook then
        return original_func()
      end

      local enabled_groups = dynamic_hook.enabled_groups
      if not enabled_groups[group_name] then
        return original_func()
      end
    end

    if handlers.before_mut then
      local ok, err = pcall(handlers.before_mut)
      if not ok then
        ngx.log(ngx.WARN,
                string.format("failed to run before_mut hook of %s: %s",
                              group_name, err))
      end
    end

    if handlers.befores then
      for _, func in ipairs(handlers.befores) do
        local ok, err = pcall(func)
        if not ok then
          ngx.log(ngx.WARN,
                  string.format("failed to run before hook of %s: %s",
                                group_name, err))
        end
      end
    end

    local r0, r1, r2, r3, r4, r5, r6, r7 = original_func()

    if handlers.after_mut then
      local ok, err = pcall(handlers.after_mut, r0, r1, r2, r3, r4, r5, r6, r7)
      if not ok then
        ngx.log(ngx.WARN,
                string.format("failed to run after_mut hook of %s: %s",
                              group_name, err))
      end
    end

    if handlers.afters then
      for _, func in ipairs(handlers.afters) do
        local ok, err = pcall(func, r0, r1, r2, r3, r4, r5, r6, r7)
        if not ok then
          ngx.log(ngx.WARN,
                  string.format("failed to run after hook of %s: %s",
                                group_name, err))
        end
      end
    end

    return r0, r1, r2, r3, r4, r5, r6, r7
  end
end


local function wrap_function_varargs(always_enabled_groups, group_name, original_func, handlers)
  return function(...)
    if not always_enabled_groups[group_name] then
      local dynamic_hook = ngx.ctx.dynamic_hook
      if not dynamic_hook then
        return original_func(...)
      end

      local enabled_groups = dynamic_hook.enabled_groups
      if not enabled_groups[group_name] then
        return original_func(...)
      end
    end

    -- before_mut is not supported for varargs functions

    if handlers.befores then
      for _, func in ipairs(handlers.befores) do
        local ok, err = pcall(func, ...)
        if not ok then
          ngx.log(ngx.WARN,
                  string.format("failed to run before hook of %s: %s",
                                group_name, err))
        end
      end
    end

    local r0, r1, r2, r3, r4, r5, r6, r7 = original_func(...)

    if handlers.after_mut then
      local ok, err = pcall(handlers.after_mut, r0, r1, r2, r3, r4, r5, r6, r7)
      if not ok then
        ngx.log(ngx.WARN,
                string.format("failed to run after_mut hook of %s: %s",
                              group_name, err))
      end
    end

    if handlers.afters then
      for _, func in ipairs(handlers.afters) do
        local ok, err = pcall(func, r0, r1, r2, r3, r4, r5, r6, r7)
        if not ok then
          ngx.log(ngx.WARN,
                  string.format("failed to run after hook of %s: %s",
                                group_name, err))
        end
      end
    end

    return r0, r1, r2, r3, r4, r5, r6, r7
  end
end


function _M.generate_wrap_function(max_args)
  if max_args == 0 then
    return warp_function_0
  end

  if max_args == "varargs" then
    return wrap_function_varargs
  end

  local args = "a0" -- the 1st arg must be named as "a0" as
                    -- it will be used in the error log

  for i = 2, max_args do
    args = args .. ", a" .. i
  end

  local func = assert(loadstring(string.format(TEMPLATE, args, args, args, args, args, args, args)))()
  assert(type(func) == "function", "failed to generate wrap function: " .. tostring(func))
  return func
end

return _M
