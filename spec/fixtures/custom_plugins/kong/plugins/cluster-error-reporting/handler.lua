local Plugin =  {
  VERSION = "6.6.6",
  PRIORITY = 1000,
}

local clustering = require("kong.clustering")
local saved_init_dp_worker = clustering.init_dp_worker

-- monkey-patch cluster initializer so that konnect_mode is
-- always enabled
clustering.init_dp_worker = function(self, ...)
  self.conf.konnect_mode = true
  return saved_init_dp_worker(self, ...)
end


local declarative = require("kong.db.declarative")
local saved_load_into_cache = declarative.load_into_cache_with_events

-- ...and monkey-patch this to throw an exception on demand
declarative.load_into_cache_with_events = function(...)
  local fh = io.open(kong.configuration.prefix .. "/throw-an-exception")
  if fh then
    local err = fh:read("*a") or "oh no!"
    ngx.log(ngx.ERR, "throwing an exception!")
    error(err)
  end

  return saved_load_into_cache(...)
end

return Plugin
