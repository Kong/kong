return function(options)
  options = options or {}

  if options.cli then
    ngx.IS_CLI = true
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
            local lvl = 1
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
            error("math.randomseed() must be called in init_worker", 2)
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
