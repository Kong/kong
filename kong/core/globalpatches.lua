local ran_before

return function(options)

  if ran_before then
    ngx.log(ngx.WARN, debug.traceback("attempt to re-run the globalpatches", 2))
    return
  end
  ngx.log(ngx.DEBUG, "installing the globalpatches")
  ran_before = true



  options = options or {}
  local meta = require "kong.meta"

  _G._KONG = {
    _NAME = meta._NAME,
    _VERSION = meta._VERSION
  }

  if options.cli then
    ngx.IS_CLI = true
    ngx.exit = function() end
  end



  do  -- implement a Lua based shm for: cli (and hence rbusted)

    if options.cli then
      -- ngx.shared.DICT proxy
      -- https://github.com/bsm/fakengx/blob/master/fakengx.lua
      -- with minor fixes and addtions such as exptime
      --
      -- See https://github.com/openresty/resty-cli/pull/12
      -- for a definitive solution ot using shms in CLI
      local SharedDict = {}
      local function set(data, key, value)
        data[key] = {
          value = value,
          info = {expired = false}
        }
      end
      function SharedDict:new()
        return setmetatable({data = {}}, {__index = self})
      end
      function SharedDict:get(key)
        return self.data[key] and self.data[key].value, nil
      end
      function SharedDict:set(key, value)
        set(self.data, key, value)
        return true, nil, false
      end
      SharedDict.safe_set = SharedDict.set
      function SharedDict:add(key, value, exptime)
        if self.data[key] ~= nil then
          return false, "exists", false
        end

        if exptime then
          ngx.timer.at(exptime, function()
            self.data[key] = nil
          end)
        end

        set(self.data, key, value)
        return true, nil, false
      end
      function SharedDict:replace(key, value)
        if self.data[key] == nil then
          return false, "not found", false
        end
        set(self.data, key, value)
        return true, nil, false
      end
      function SharedDict:delete(key)
        if self.data[key] ~= nil then
          self.data[key] = nil
        end
        return true
      end
      function SharedDict:incr(key, value)
        if not self.data[key] then
          return nil, "not found"
        elseif type(self.data[key].value) ~= "number" then
          return nil, "not a number"
        end
        self.data[key].value = self.data[key].value + value
        return self.data[key].value, nil
      end
      function SharedDict:flush_all()
        for _, item in pairs(self.data) do
          item.info.expired = true
        end
      end
      function SharedDict:flush_expired(n)
        local data = self.data
        local flushed = 0

        for key, item in pairs(self.data) do
          if item.info.expired then
            data[key] = nil
            flushed = flushed + 1
            if n and flushed == n then
              break
            end
          end
        end
        self.data = data
        return flushed
      end
      function SharedDict:get_keys(n)
        n = n or 1024
        local i = 0
        local keys = {}
        for k in pairs(self.data) do
          keys[#keys+1] = k
          i = i + 1
          if n ~= 0 and i == n then
            break
          end
        end
        return keys
      end

      -- hack
      _G.ngx.shared = setmetatable({}, {
        __index = function(self, key)
          local shm = rawget(self, key)
          if not shm then
            shm = SharedDict:new()
            rawset(self, key, SharedDict:new())
          end
          return shm
        end
      })
    end

  end



  do -- patch luassert when running in the Busted test environment

    if options.rbusted then
      -- patch luassert's 'assert' to fix the 'third' argument problem
      -- see https://github.com/Olivine-Labs/luassert/pull/141
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



  do -- randomseeding patch for: cli, rbusted and OpenResty

    if options.rbusted then

      -- we need this version because we cannot hit the ffi, same issue
      -- as with the semaphore patch
      -- only used for running tests
      local randomseed = math.randomseed
      local seeds = {}

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
        local seed = seeds[ngx.worker.pid()]
        if not seed then
          -- If we're in runtime nginx, we have multiple workers so we _only_
          -- accept seeding when in the 'init_worker' phase.
          -- That is because that phase is the earliest one before the
          -- workers have a chance to process business logic, and because
          -- if we'd do that in the 'init' phase, the Lua VM is not forked
          -- yet and all workers would end-up using the same seed.
          if not options.cli and ngx.get_phase() ~= "init_worker" then
            ngx.log(ngx.WARN, debug.traceback("math.randomseed() must be "..
                "called in init_worker context", 2))
          end

          seed = ngx.time() + ngx.worker.pid()
          ngx.log(ngx.DEBUG, "random seed: ", seed, " for worker nb ", ngx.worker.id(),
                             " (pid: ", ngx.worker.pid(), ")")
          randomseed(seed)
          seeds[ngx.worker.pid()] = seed
        else
          ngx.log(ngx.DEBUG, debug.traceback("attempt to seed random number "..
              "generator, but already seeded with: "..tostring(seed), 2))
        end

        return seed
      end

    else

      -- this version of the randomseeding patch is required for
      -- production, but doesn't work in tests, due to the ffi dependency
      local util = require "kong.tools.utils"
      local seeds = {}
      local randomseed = math.randomseed

      _G.math.randomseed = function()
        local seed = seeds[ngx.worker.pid()]
        if not seed then
          if not options.cli and ngx.get_phase() ~= "init_worker" then
            ngx.log(ngx.WARN, debug.traceback("math.randomseed() must be "..
                "called in init_worker context", 2))
          end

          local bytes, err = util.get_rand_bytes(8)
          if bytes then
            ngx.log(ngx.DEBUG, "seeding PRNG from OpenSSL RAND_bytes()")

            local t = {}
            for i = 1, #bytes do
              local byte = string.byte(bytes, i)
              t[#t+1] = byte
            end
            local str = table.concat(t)
            if #str > 12 then
              -- truncate the final number to prevent integer overflow,
              -- since math.randomseed() could get cast to a platform-specific
              -- integer with a different size and get truncated, hence, lose
              -- randomness.
              -- double-precision floating point should be able to represent numbers
              -- without rounding with up to 15/16 digits but let's use 12 of them.
              str = string.sub(str, 1, 12)
            end
            seed = tonumber(str)
          else
            ngx.log(ngx.ERR, "could not seed from OpenSSL RAND_bytes, seeding ",
                             "PRNG with time and worker pid instead (this can ",
                             "result to duplicated seeds): ", err)

            seed = ngx.now()*1000 + ngx.worker.pid()
          end

          ngx.log(ngx.DEBUG, "random seed: ", seed, " for worker nb ",
                              ngx.worker.id())

          if not options.cli then
            local ok, err = ngx.shared.kong:safe_set("pid: " .. ngx.worker.pid(), seed)
            if not ok then
              ngx.log(ngx.WARN, "could not store PRNG seed in kong shm: ", err)
            end
          end

          randomseed(seed)
          seeds[ngx.worker.pid()] = seed
        else
          ngx.log(ngx.DEBUG, debug.traceback("attempt to seed random number "..
              "generator, but already seeded with: "..tostring(seed), 2))
        end

        return seed
      end
    end

  end



  do  -- pure lua semaphore patch for: rbusted

    if options.rbusted then
      -- when testing, busted will cleanup the global environment for test
      -- insulation. This includes the `ffi` module. Because the dns module
      -- is loaded ahead of busted, it (and its dependencies) become part
      -- of the global environment that busted does NOT cleanup.
      -- The semaphore library depends on the ffi, and hence prevents it
      -- from being GCed. The result is that reloading other libraries will
      -- generate `attempt to redefine` errors when the ffi stuff is defined
      -- (because they weren't GCed).
      -- __NOTE__: though it works for now, it remains a bad idea to recycle
      -- the ffi module as it is c-based and will result in unpredictable
      -- segfaults. At the cost of reduced test insulation the busted option
      -- `--no-auto-insulation` could/should be used.
      package.loaded["ngx.semaphore"] = {
        new = function(n)
          return {
            resources = n or 0,
            waiting = 0,
            post = function(self, n)
              self.resources = self.resources + (n or 1)
            end,
            wait = function(self, timeout) -- timeout = seconds
              if self.resources > 0 then
                self.resources = self.resources - 1
                return true
              end
              self.waiting = self.waiting + 1
              local expire = ngx.now() + timeout
              while expire > ngx.now() do
                ngx.sleep(0.001)
                if self.resources > 0 then
                  self.resources = self.resources - 1
                  self.waiting = self.waiting - 1
                  return true
                end
              end
              self.waiting = self.waiting - 1
              return nil, "timeout"
            end,
            count = function(self)
              if self.resources > 0 then return self.resources end
              return -self.waiting
            end
          }
        end
      }
    end

  end


  do -- cosockets connect patch for dns resolution for: cli, rbusted and OpenResty
    if options.cli then
      -- Because the CLI runs in `xpcall`, we cannot use yielding cosockets.
      -- Hence, we need to stick to luasocket when using cassandra or pgmoon
      -- in the CLI.
      for _, namespace in ipairs({"cassandra", "pgmoon-mashape"}) do
        local socket = require(namespace .. ".socket")
        socket.force_luasocket(ngx.get_phase(), true)
      end

    else
      for _, namespace in ipairs({"cassandra", "pgmoon-mashape"}) do
        local socket = require(namespace .. ".socket")
        socket.force_luasocket("init_worker", true)
      end

      local string_sub = string.sub
      --- Patch the TCP connect and UDP setpeername methods such that all
      -- connections will be resolved first by the internal DNS resolver.
      -- STEP 1: load code that should not be using the patched versions
      require "resty.dns.resolver"  -- will cache TCP and UDP functions
      -- STEP 2: forward declaration of locals to hold stuff loaded AFTER patching
      local toip
      -- STEP 3: store original unpatched versions
      local old_tcp = ngx.socket.tcp
      local old_udp = ngx.socket.udp
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
      _G.ngx.socket.udp = function(...)
        local sock = old_udp(...)
        local old_setpeername = sock.setpeername

        sock.setpeername = function(s, host, port)
          local target_ip, target_port
          if string_sub(host, 1, 5) == "unix:" then
            target_ip = host  -- unix domain socket, so just maintain the named values
          else
            target_ip, target_port = toip(host, port)
            if not target_ip then
              return nil, "[toip() name lookup failed]:"..tostring(target_port)
            end
          end
          return old_setpeername(s, target_ip, target_port)
        end
        return sock
      end
      -- STEP 5: load code that should be using the patched versions, if any (because of dependency chain)
      toip = require("resty.dns.client").toip  -- this will load utils and penlight modules for example
    end
  end
end

