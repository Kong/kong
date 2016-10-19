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
end
