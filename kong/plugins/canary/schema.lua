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
  if steps <= 1 then
    return false, "'steps' must be greater than 1"
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


local function check_upstream_host(upstream_host)
  if upstream_host and not utils.check_hostname(upstream_host) then
    return false, "'upstream_host' must be a valid hostname"
  end

  return true
end

local function check_upstream_port(upstream_port)
  if upstream_port and (upstream_port < 1 or upstream_port > 65535) then
    return false, "'upstream_port' must be a valid portnumber (1 - 65535)"
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
      type = "number",
      func = check_start
    },
    hash = {        -- what element to use for hashing to the target
      type    = "string",
      default = "consumer",
      enum    = { "consumer", "ip", "none", "whitelist", "blacklist" },
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
    upstream_host = {  -- target hostname
      type = "string",
      func = check_upstream_host
    },
    upstream_port = {  -- target port
      type = "number",
      func = check_upstream_port
    },
    upstream_uri = {   -- target uri
      type = "string",
      func = check_upstream_uri
    },
    upstream_fallback = {
      type = "boolean",
      default = false,
      required = true,
    },
    groups = {  -- white- or blacklists
      type = "array",
    },
  },
  self_check = function(_, conf, _, is_update)
    if not is_update and not conf.upstream_uri and not conf.upstream_host and not conf.upstream_port then
      return false, Errors.schema "either 'upstream_uri', 'upstream_host', or 'upstream_port' must be provided"
    end

    if not conf.upstream_host and conf.upstream_fallback then
      return false, Errors.schema "'upstream_fallback' requires 'upstream_host'"
    end

    if conf.hash ~= "whitelist" and conf.hash ~= "blacklist" then
      if not is_update and not conf.percentage and not conf.start then
        return false, Errors.schema "either 'percentage' or 'start' must be provided"
      end
    end

    return true
  end,
}
