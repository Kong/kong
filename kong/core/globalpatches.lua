local meta = require "kong.meta"
local randomseed = math.randomseed

_G._KONG = {
  _NAME = meta._NAME,
  _VERSION = meta._VERSION
}

local seed_registry = {}

--- Seeds the random generator, use with care.
-- The uuid.seed() method will create a unique seed per worker
-- process, using a combination of both time and the worker's pid.
-- We only allow it to be called once to prevent third-party modules
-- from overriding our correct seed (many modules make a wrong usage
-- of `math.randomseed()` by calling it multiple times or do not use
-- unique seed for Nginx workers).
-- luacheck: globals math
_G.math.randomseed = function()
  local pid = ngx.worker.pid()
  local seed
  
  if not seed_registry[pid] then
    seed = ngx.time() + ngx.worker.pid()
    ngx.log(ngx.DEBUG, "random seed: ", seed, " for worker ", pid)
    randomseed(seed)
    seed_registry[pid] = { 
      seed = seed, 
      trace = debug.traceback("Initially seeded from context '"..ngx.get_phase().."':"),
    }
  else
    seed = seed_registry[pid].seed
    ngx.log(ngx.ERR, debug.traceback("attempt to re-seed random number generator")..
                                     "\n"..seed_registry[pid].trace)
  end

  return seed
end

