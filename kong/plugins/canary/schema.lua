local utils  = require "kong.tools.utils"
local Errors = require "kong.dao.errors"


local function check_start(start)
  local time = math.floor(ngx.now())
  if start and start < time then
    return false, "'start' cannot be in the past"
  end

  return true
end


local function check_steps(steps)
  if steps <= 0 then
    return false, "'steps' must be greater than 0"
  end

  return true
end


local function check_duration(duration)
  if duration <= 0 then
    return false, "'duration' must be greater than 0"
  end

  return true
end


local function check_percentage(percentage)
  if percentage then
    if percentage < 0 or percentage > 100 then
      return false, "'percentage' must be in between 0 and 100"
    end
  end

  return true
end


local function check_upstream_target(upstream_target)
  if upstream_target and not utils.check_hostname(upstream_target) then
    return false, "'upstream_target' must be a valid hostname"
  end

  return true
end

local function check_upstream_uri(upstream_uri)
  if upstream_uri and upstream_uri == "" then
    return false, "'upstream_uri' must not be empty"
  end

  return true
end

return {
  no_consumer = true,
  fields = {
    start = {       -- when to start the release (seconds since epoch)
      type    = "number",
      func    = check_start
    },
    hash = {        -- what element to use for hashing to the target
      type    = "string",
      default = "consumer",
      enum    = { "consumer", "ip" },
    },
    duration = {    -- how long should the transaction take (seconds)
      type    = "number",
      default = 60 * 60,
      func    = check_duration
    },
    steps = {       -- how many steps
      type    = "number",
      default = 1000,
      func    = check_steps,
    },
    percentage = {  -- fixed % of traffic, if given overrides start/duration
      type = "number",
      func = check_percentage,
    },
    upstream_target = {  -- target hostname (upstream_url == a, this is b)
      type = "string",
      func = check_upstream_target
    },
    upstream_uri = {   -- target uri (upstream_url == a, this is b)
      type = "string",
      func = check_upstream_uri
    },
  },
  self_check = function(_, conf, dao, is_update)
    if not is_update and not conf.upstream_uri and not conf.upstream_target then
      return false, Errors.schema "either 'upstream_uri' or 'upstream_target' must be provided"
    end

    return true
  end,
}
