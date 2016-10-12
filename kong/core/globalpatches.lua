return function(options)

  options = options or {}
  local meta = require "kong.meta"

  _G._KONG = {
    _NAME = meta._NAME,
    _VERSION = meta._VERSION
  }



  do  -- patch the nginx exit method when running under the cli

    if options.cli then
      ngx.IS_CLI = true
      ngx.exit = function()end
    end

  end



  do -- patch luassert when running in the Busted test enviornment
    
    if options.rbusted then
      -- patch luassert's 'assert' because very often we use the Lua idiom:
      -- local res = assert(some_method())
      -- in our tests.
      -- luassert's 'assert' would error out in case the assertion fails, and
      -- if 'some_method()' returns a third return value because we attempt to
      -- perform arithmetic (+1) to the 'level' argument of 'assert'.
      -- This error would often supersed the actual error (arg #2) and be painful
      -- to debug.
      local assert = require "luassert.assert"
      local assert_mt = getmetatable(assert)
      if assert_mt then
        assert_mt.__call = function(self, bool, message, level, ...)
          if not bool then
            local lvl = 2
            if type(level) == "number" then
              lvl = level + 1
            end
            error(message or "assertion failed!", lvl)
          end
          return bool, message, level, ...
        end
      end
    end

  end
  
  
  
  do -- randomseeding patch

    local randomseed = math.randomseed
    local seed

    --- Seeds the random generator, use with care.
    -- Once - properly - seeded, this method is replaced with a stub
    -- one. This is to enforce best-practises for seeding in ngx_lua,
    -- and prevents third-party modules from overriding our correct seed
    -- (many modules make a wrong usage of `math.randomseed()` by calling
    -- it multiple times or do not use unique seed for Nginx workers).
    --
    -- This patched method will create a unique seed per worker process,
    -- using a combination of both time and the worker's pid.
    -- luacheck: globals math
    _G.math.randomseed = function()
      if not seed then
        -- If we're in runtime nginx, we have multiple workers so we _only_
        -- accept seeding when in the 'init_worker' phase.
        -- That is because that phase is the earliest one before the
        -- workers have a chance to process business logic, and because
        -- if we'd do that in the 'init' phase, the Lua VM is not forked
        -- yet and all workers would end-up using the same seed.
        if not options.cli and ngx.get_phase() ~= "init_worker" then
          ngx.log(ngx.ERR, debug.traceback("math.randomseed() must be called in init_worker"))
        end

        seed = ngx.time() + ngx.worker.pid()
        ngx.log(ngx.DEBUG, "random seed: ", seed, " for worker nb ", ngx.worker.id(),
                           " (pid: ", ngx.worker.pid(), ")")
        randomseed(seed)
      else
        ngx.log(ngx.DEBUG, "attempt to seed random number generator, but ",
                           "already seeded with ", seed)
      end

      return seed
    end

  end



  do -- cosockets connect patch for dns resolution

    --- Patch the TCP connect method such that all connections will be resolved
    -- first by the internal DNS resolver. 
    -- STEP 1: load code that should not be using the patched versions
    require "resty.dns.resolver"  -- will cache TCP and UDP functions
    -- STEP 2: forward declaration of locals to hold stuff loaded AFTER patching
    local toip
    -- STEP 3: store original unpatched versions
    local old_tcp = ngx.socket.tcp
    -- STEP 4: patch globals
    _G.ngx.socket.tcp = function(...)
      local sock = old_tcp(...)
      local old_connect = sock.connect
      
      sock.connect = function(s, host, port, sock_opts)
        local target_ip, target_port = toip(host, port)
        if not target_ip then 
          return nil, "[toip() name lookup failed]:"..tostring(target_port)
        else
          -- need to do the extra check here: https://github.com/openresty/lua-nginx-module/issues/860
          if not sock_opts then
            return old_connect(s, target_ip, target_port)
          else
            return old_connect(s, target_ip, target_port, sock_opts)
          end
        end
      end
      return sock
    end
    -- STEP 5: load code that should be using the patched versions, if any (because of dependency chain)
    toip = require("dns.client").toip  -- this will load utils and penlight modules for example

  end



  do -- patch for LuaSocket tcp sockets, block usage in cli.

    if options.cli then
      local socket = require "socket"
      socket.tcp = function(...)
        error("should not be using this")
      end
    end
  
  end



  do -- patch cassandra driver to use the cosockets anyway, as we've patched them above already

    require("cassandra.socket")  --just pre-loading the module will do
  
  end
  
  
  --[[ no longer needed, since pulling 0.9.2?

  do -- Cassandra cache-shm patch

    --- Patch cassandra driver.
    -- The cache module depends on an `shm` which isn't available on the `resty` cli.
    -- in non-nginx Lua it uses a stub. So for the cli make it think it's non-nginx.
    if options.cli then
      local old_ngx = _G.ngx
      _G.ngx = nil
      require "cassandra.cache"
      _G.ngx = old_ngx
    end
  end



  do -- cassandra resty-lock patch
    
    --- stub for resty.lock module which isn't available in the `resty` cli because it
    -- requires an `shm`.
    if options.cli then
      package.loaded["resty.lock"] = {
          new = function()
            return {
              lock = function(self, key)
                return 0   -- cli is single threaded, so a lock always succeeds
              end,
              unlock = function(self, key)
                return 1   -- same as above, always succeeds
              end
            }
          end,
        }
    end
  end
  --]]
end