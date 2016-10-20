return function(options)
  options = options or {}

  if options.cli then
    ngx.IS_CLI = true

    ngx.exit = function()end

    -- force LuaSocket usage to resolve `/etc/hosts` until
    -- supported by resty-cli.
    -- See https://github.com/Mashape/kong/issues/1523
    for _, namespace in ipairs({"cassandra", "pgmoon-mashape"}) do
      local socket = require(namespace .. ".socket")
      socket.force_luasocket(ngx.get_phase(), true)
    end

    do
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
        self.data[key] = nil
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

  if options.rbusted then

    do
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

  else

    do
      local meta = require "kong.meta"

      _G._KONG = {
        _NAME = meta._NAME,
        _VERSION = meta._VERSION
      }
    end

    do
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
            local debug = require "debug"
            ngx.log(ngx.WARN, "math.randomseed() must be called in init_worker context\n",
                              debug.traceback())
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
  end
end
