local meta = require "kong.meta"
local randomseed = math.randomseed

_G._KONG = {
  _NAME = meta._NAME,
  _VERSION = meta._VERSION
}

local seed

--- Seeds the random generator, use with care.
-- The uuid.seed() method will create a unique seed per worker
-- process, using a combination of both time and the worker's pid.
-- We only allow it to be called once to prevent third-party modules
-- from overriding our correct seed (many modules make a wrong usage
-- of `math.randomseed()` by calling it multiple times or do not use
-- unique seed for Nginx workers).
-- luacheck: globals math
_G.math.randomseed = function()
  if not seed then
    if ngx.get_phase() ~= "init_worker" then
      error("math.randomseed() must be called in init_worker", 2)
    end

    seed = ngx.time() + ngx.worker.pid()
    ngx.log(ngx.DEBUG, "random seed: ", seed, " for worker n", ngx.worker.id(),
                       " (pid: ", ngx.worker.pid(), ")")
    randomseed(seed)
  else
    ngx.log(ngx.DEBUG, "attempt to seed random number generator, but ",
                       "already seeded with ", seed)
  end

  return seed
end
