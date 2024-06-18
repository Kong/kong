-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- imports
--

local redis = require("resty.redis")
local urls = require("socket.url")

--
-- private vars
--

local REDIS_TIMEOUT = 1000

--
-- public functions
--

-- Initialize a Redis client and verify connectivity.
--
-- @param opts an options table including things like the URL, auth, and TLS configuration
-- @return the Redis client
-- @return nothing. throws an error if any
local function create(opts)
  local url = opts.url
  if not url then
    return nil, "missing URL"
  end

  local url, err = urls.parse(url)
  if err then
    return nil, err
  end

  local red = redis:new()
  red:set_timeouts(REDIS_TIMEOUT, REDIS_TIMEOUT, REDIS_TIMEOUT)
  local redis_options = {
    ssl = true,
    ssl_verify = true,
  }
  if opts.tls then
    redis_options.ssl = opts.tls.ssl
    redis_options.ssl_verify = opts.tls.ssl_verify
  end

  local _, err = red:connect(url.host, tonumber(url.port), redis_options)
  if err then
    return red, err
  end

  if opts.auth and opts.auth.password then
    local ok, err = red:auth(opts.auth.password)
    if err then
      return red, err
    end
    if not ok then
      return red, "failed to authenticate"
    end
  end

  local _, err = red:ping()
  return red, err
end

--
-- module
--

return {
  -- functions
  create = create
}
