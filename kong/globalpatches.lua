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


  if options.cli then
    -- disable the _G write guard alert log introduced in OpenResty 1.15.8.1
    -- when in CLI or when running tests in resty-cli
    --local _G_mt = getmetatable(_G)
    setmetatable(_G, nil)
  end


  _G._KONG = {
    _NAME = meta._NAME,
    _VERSION = meta._VERSION
  }

  if options.cli then
    ngx.IS_CLI = true
    -- luacheck: globals ngx.exit
    ngx.exit = function() end
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
      -- with minor fixes and additions such as exptime
      --
      -- See https://github.com/openresty/resty-cli/pull/12
      -- for a definitive solution of using shms in CLI
      local SharedDict = {}
      local function set(data, key, value, expire_at)
        data[key] = {
          value = value,
          info = {expire_at = expire_at}
        }
      end
      function SharedDict:new()
        return setmetatable({data = {}}, {__index = self})
      end
      function SharedDict:capacity()
        return 0
      end
      function SharedDict:free_space()
        return 0
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

        local expire_at = nil

        if exptime then
          ngx.timer.at(exptime, function()
            self.data[key] = nil
          end)
          expire_at = ngx.now() + exptime
        end

        set(self.data, key, value, expire_at)
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
      function SharedDict:incr(key, value, init, init_ttl)
        if not self.data[key] then
          if not init then
            return nil, "not found"
          else
            self.data[key] = { value = init, info = {} }
            if init_ttl then
              self.data[key].info.expire_at = ngx.now() + init_ttl
              ngx.timer.at(init_ttl, function()
                self.data[key] = nil
              end)
            end
          end
        elseif type(self.data[key].value) ~= "number" then
          return nil, "not a number"
        end
        self.data[key].value = self.data[key].value + value
        return self.data[key].value, nil
      end
      function SharedDict:flush_all()
        for _, item in pairs(self.data) do
          item.info.expire_at = ngx.now()
        end
      end
      function SharedDict:flush_expired(n)
        local data = self.data
        local flushed = 0

        for key, item in pairs(self.data) do
          if item.info.expire_at and item.info.expire_at <= ngx.now() then
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
      function SharedDict:ttl(key)
        local item = self.data[key]
        if item == nil then
          return nil, "not found"
        else
          local expire_at = item.info.expire_at
          if expire_at == nil then
            return 0
          else
            local remaining = expire_at - ngx.now()
            if remaining < 0 then
              return nil, "not found"
            else
              return remaining
            end
          end
        end
      end

      -- hack
      _G.ngx.shared = setmetatable({}, {
        __index = function(self, key)
          local shm = rawget(self, key)
          if not shm then
            shm = SharedDict:new()
            rawset(self, key, shm)
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
    -- it multiple times or by not using unique seeds for Nginx workers).
    --
    -- This patched method will create a unique seed per worker process,
    -- using a combination of both time and the worker's pid.
    local util = require "kong.tools.utils"
    local seeds = {}
    local randomseed = math.randomseed

    _G.math.randomseed = function()
      local seed = seeds[ngx.worker.pid()]
      if not seed then
        if not options.cli
          and (ngx.get_phase() ~= "init_worker" and ngx.get_phase() ~= "init")
        then
          ngx.log(ngx.WARN, debug.traceback("math.randomseed() must be " ..
              "called in init or init_worker context", 2))
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

    -- need to do the extra check here: https://github.com/openresty/lua-nginx-module/issues/860
    local function strip_nils(first, second)
      if second then
        return first, second
      elseif first then
        return first
      end
    end

    local function resolve_connect(f, sock, host, port, opts)
      if sub(host, 1, 5) ~= "unix:" then
        local try_list
        host, port, try_list = toip(host, port)
        if not host then
          return nil, "[cosocket] DNS resolution failed: " .. tostring(port) ..
                      ". Tried: " .. tostring(try_list)
        end
      end

      return f(sock, host, strip_nils(port, opts))
    end

    local function tcp_resolve_connect(sock, host, port, opts)
      return resolve_connect(old_tcp_connect, sock, host, port, opts)
    end

    local function udp_resolve_setpeername(sock, host, port)
      return resolve_connect(old_udp_setpeername, sock, host, port)
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

