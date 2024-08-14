-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cache        = require("kong.plugins.upstream-oauth.cache")
local oauth_client = require("kong.plugins.upstream-oauth.oauth-client")
local meta         = require("kong.meta")

local kong         = kong
local ngx          = ngx
local plugin       = {
  PRIORITY = 760,
  VERSION = meta.core_version,
}

-- Formats the response to the consumer if this plugin blocks an incoming request.
local function idp_error_response(conf)
  local status = conf.behavior.idp_error_response_status_code
  local headers = {}
  local content = ""

  if conf.behavior.idp_error_response_content_type ~= "" then
    headers["Content-Type"] = conf.behavior.idp_error_response_content_type
  end

  if conf.behavior.idp_error_response_body_template ~= "" then
    content = string.gsub(conf.behavior.idp_error_response_body_template, "{{status}}", status)
    content = string.gsub(content, "{{message}}", conf.behavior.idp_error_response_message)
  end

  kong.response.exit(status, content, headers)
end

local function purge_on_upstream_auth_failure(_, conf, key)
  local strategy = cache.strategy({
    strategy_name = conf.cache.strategy,
    strategy_opts = conf.cache[conf.cache.strategy],
  })

  local success, err = strategy:purge(key)
  if not success then
    kong.log.err("Failed to purge cached token with key ", key, " ", err)
  end
end

function plugin:access(conf)
  local strategy = cache.strategy({
    strategy_name = conf.cache.strategy,
    strategy_opts = conf.cache[conf.cache.strategy],
  })

  local key = cache.key(conf.oauth)

  kong.log.debug("Retrieving cached access token for key: ", key)
  local token, err = strategy:fetch(key)
  if err then
    kong.log.warn(err)
  end

  if not token then
    kong.log.debug("No cached access token for key: ", key, " retrieving new token.")
    local client = oauth_client.new(conf.client, conf.oauth)
    token, err = client:get_token()
    if err or not token then
      kong.log.err("Failed to retrieve token from IdP: ", err)
      return idp_error_response(conf)
    end
    kong.log.debug("Successfully retrieved new access token for key: ", key)

    -- Access token expiry
    local ttl = conf.cache.default_ttl
    if token.expires_in ~= nil then
      ttl = math.max(cache.constants.MIN_TTL, token.expires_in - conf.cache.eagerly_expire)
      kong.log.debug("Token expires in ", token.expires_in, "s. Eagerly expiring in ", ttl, "s")
    else
      kong.log.debug("Token does not expire, using default ttl: ", conf.cache.default_ttl)
    end

    local _, err = strategy:store(key, token, ttl)
    if err then
      kong.log.warn(err)
    end
  end

  local prefix = token.token_type or "Bearer"
  kong.service.request.set_header(conf.behavior.upstream_access_token_header_name, prefix .. " " .. token.access_token)
end

function plugin:header_filter(conf)
  if (conf.behavior.purge_token_on_upstream_status_codes and #conf.behavior.purge_token_on_upstream_status_codes > 0) then
    local status = kong.service.response.get_status()
    for _, value in ipairs(conf.behavior.purge_token_on_upstream_status_codes) do
      if value == status then
        local key = cache.key(conf.oauth)
        kong.log.debug("Purging cached token with key ", key, " due to upstream failure with status code ", status)

        -- Need to run this in timer as cosockets not available in header_filter and redis cache requires this
        -- (https://github.com/openresty/lua-nginx-module#cosockets-not-available-everywhere)
        ngx.timer.at(0, purge_on_upstream_auth_failure, conf, key)
        break
      end
    end
  end
end

return plugin
