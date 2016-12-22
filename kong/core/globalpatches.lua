return function(opts)
  opts = opts or {}

  do
    local meta = require "kong.meta"

    _G._KONG = {
      _NAME = meta._NAME,
      _VERSION = meta._VERSION
    }
  end

  do
    local util = require "kong.tools.utils"
    local seed
    local randomseed = math.randomseed

    _G.math.randomseed = function()
      if not seed then
        if not opts.cli and ngx.get_phase() ~= "init_worker" then
          ngx.log(ngx.WARN, "math.randomseed() must be called in init_worker ",
          "context\n", debug.traceback('', 2)) -- nil [message] arg doesn't work with level
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

        if not opts.cli then
          local ok, err = ngx.shared.kong:safe_set("pid: " .. ngx.worker.pid(), seed)
          if not ok then
            ngx.log(ngx.WARN, "could not store PRNG seed in kong shm: ", err)
          end
        end

        randomseed(seed)
      else
        ngx.log(ngx.DEBUG, "attempt to seed random number generator, but ",
        "already seeded with: ", seed, "\n",
        debug.traceback('', 2)) -- nil [message] arg doesn't work with level
      end

      return seed
    end
  end

  if opts.cli then
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
