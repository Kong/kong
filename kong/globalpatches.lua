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
    -- luacheck: globals ngx.exit
    ngx.exit = function() end
  end



  do -- deal with ffi re-loading issues

    if options.rbusted then
      -- pre-load the ffi module, such that it becomes part of the environment
      -- and Busted will not try to GC and reload it. The ffi is not suited
      -- for that and will occasionally segfault if done so.
      local ffi = require "ffi"

      -- Now patch ffi.cdef to only be called once with each definition
      local old_cdef = ffi.cdef
      local exists = {}
      ffi.cdef = function(def)
        if exists[def] then
          return
        end
        exists[def] = true
        return old_cdef(def)
      end

    end

  end



  do -- implement `sleep` in the `init_worker` context

    -- initialization code regularly uses the shm and locks.
    -- the resty-lock is based on sleeping while waiting, but that api
    -- is unavailable. Hence we implement a BLOCKING sleep, only in
    -- the init_worker context.
    local get_phase= ngx.get_phase
    local ngx_sleep = ngx.sleep
    local alternative_sleep = require("socket").sleep

    -- luacheck: globals ngx.sleep
    ngx.sleep = function(s)
      if get_phase() == "init_worker" then
        ngx.log(ngx.WARN, "executing a blocking 'sleep' (", s, " seconds)")
        return alternative_sleep(s)
      end
      return ngx_sleep(s)
    end

  end



  do  -- implement a Lua based shm for: cli (and hence rbusted)

    if options.cli then
      -- ngx.shared.DICT proxy
      -- https://github.com/bsm/fakengx/blob/master/fakengx.lua
      -- with minor fixes and addtions such as exptime
      --
      -- See https://github.com/openresty/resty-cli/pull/12
      -- for a definitive solution of using shms in CLI
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
      SharedDict.get_stale = SharedDict.get
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
      SharedDict.safe_add = SharedDict.add
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
      function SharedDict:incr(key, value, init)
        if not self.data[key] then
          if not init then
            return nil, "not found"
          else
            self.data[key] = { value = init }
          end
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



  do -- randomseeding patch for: cli, rbusted and OpenResty

    --- Seeds the random generator, use with care.
    -- Once - properly - seeded, this method is replaced with a stub
    -- one. This is to enforce best-practices for seeding in ngx_lua,
    -- and prevents third-party modules from overriding our correct seed
    -- (many modules make a wrong usage of `math.randomseed()` by calling
    -- it multiple times or by not useing unique seeds for Nginx workers).
    --
    -- This patched method will create a unique seed per worker process,
    -- using a combination of both time and the worker's pid.
    local util = require "kong.tools.utils"
    local seeds = {}
    local randomseed = math.randomseed

    _G.math.randomseed = function()
      local seed = seeds[ngx.worker.pid()]
      if not seed then
        if not options.cli and ngx.get_phase() ~= "init_worker" then
          ngx.log(ngx.WARN, debug.traceback("math.randomseed() must be " ..
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
        ngx.log(ngx.DEBUG, debug.traceback("attempt to seed random number " ..
            "generator, but already seeded with: " .. tostring(seed), 2))
      end

      return seed
    end
  end



  do -- cosockets connect patch for dns resolution for: cli, rbusted and OpenResty
    local sub = string.sub

    --- Patch the TCP connect and UDP setpeername methods such that all
    -- connections will be resolved first by the internal DNS resolver.
    -- STEP 1: load code that should not be using the patched versions
    require "resty.dns.resolver" -- will cache TCP and UDP functions

    -- STEP 2: forward declaration of locals to hold stuff loaded AFTER patching
    local toip

    -- STEP 3: store original unpatched versions
    local old_tcp = ngx.socket.tcp
    local old_udp = ngx.socket.udp

    local old_tcp_connect
    local old_udp_setpeername

    local function tcp_resolve_connect(sock, host, port, sock_opts)
      local target_ip, target_port = toip(host, port)
      if not target_ip then
        return nil, "[toip() name lookup failed]: " .. tostring(target_port) -- err
      end

      -- need to do the extra check here: https://github.com/openresty/lua-nginx-module/issues/860
      if not sock_opts then
        return old_tcp_connect(sock, target_ip, target_port)
      end

      return old_tcp_connect(sock, target_ip, target_port, sock_opts)
    end

    local function udp_resolve_setpeername(sock, host, port)
      local target_ip, target_port

      if sub(host, 1, 5) == "unix:" then
        target_ip = host -- unix domain socket, so just maintain the named values

      else
        target_ip, target_port = toip(host, port)

        if not target_ip then
          return nil, "[toip() name lookup failed]: " .. tostring(target_port) -- err
        end
      end

      return old_udp_setpeername(sock, target_ip, target_port)
    end

    -- STEP 4: patch globals
    _G.ngx.socket.tcp = function(...)
      local sock = old_tcp(...)

      if not old_tcp_connect then
        old_tcp_connect = sock.connect
      end

      sock.connect = tcp_resolve_connect

      return sock
    end

    _G.ngx.socket.udp = function(...)
      local sock = old_udp(...)

      if not old_udp_setpeername then
        old_udp_setpeername = sock.setpeername
      end

      sock.setpeername = udp_resolve_setpeername

      return sock
    end

    -- STEP 5: load code that should be using the patched versions, if any (because of dependency chain)
    toip = require("resty.dns.client").toip  -- this will load utils and penlight modules for example
  end
end

