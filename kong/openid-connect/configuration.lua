-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http         = require "resty.http"
local codec        = require "kong.openid-connect.codec"
local debug        = require "kong.openid-connect.debug"


local setmetatable = setmetatable
local tonumber     = tonumber
local json         = codec.json
local type         = type
local byte         = string.byte
local sub          = string.sub


local INTROSPECTION_ENDPOINTS = {
  ["https://accounts.google.com"] = "https://www.googleapis.com/oauth2/v3/tokeninfo",
}


local SLASH = byte("/")


local configuration = {}


function configuration.new(oic, claims)
  local self = setmetatable({ oic = oic or {}, claims = {} }, configuration)
  if claims then
    self:reset(claims)
  end
  return self
end


function configuration.load(issuer, options, opts)
  options = options or {}
  opts    = opts    or {}

  local url
  if sub(issuer, -33) == "/.well-known/openid-configuration"
  or sub(issuer, -39) == "/.well-known/oauth-authorization-server"
  then
    url = issuer

  else
    if byte(issuer, -1) == SLASH then
      url = issuer .. ".well-known/openid-configuration"

    else
      url = issuer .. "/.well-known/openid-configuration"
    end
  end

  local keepalive
  if options.keepalive ~= nil then
    keepalive = not not options.keepalive
  elseif opts.keepalive ~= nil then
    keepalive = not not opts.keepalive
  else
    keepalive = true
  end

  local ssl_verify
  if options.ssl_verify ~= nil then
    ssl_verify = not not options.ssl_verify
  elseif opts.ssl_verify ~= nil then
    ssl_verify = not not opts.ssl_verify
  else
    ssl_verify = false
  end

  local params = {
    version    = tonumber(options.http_version) or tonumber(opts.http_version),
    query      = options.query,
    headers    = options.headers,
    body       = options.body,
    keepalive  = keepalive,
    ssl_verify = ssl_verify,
  }

  local httpc = http.new()

  local timeout = options.timeout or opts.timeout
  if timeout then
    if httpc.set_timeouts then
      httpc:set_timeouts(timeout, timeout, timeout)

    else
      httpc:set_timeout(timeout)
    end
  end

  if httpc.set_proxy_options and (options.http_proxy  or
                                  options.https_proxy or
                                  opts.http_proxy     or
                                  opts.https_proxy) then
    httpc:set_proxy_options({
      http_proxy                = options.http_proxy                or opts.http_proxy,
      http_proxy_authorization  = options.http_proxy_authorization  or opts.http_proxy_authorization,
      https_proxy               = options.https_proxy               or opts.https_proxy,
      https_proxy_authorization = options.https_proxy_authorization or opts.https_proxy_authorization,
      no_proxy                  = options.no_proxy                  or opts.no_proxy,
    })
  end

  local res = httpc:request_uri(url, params)
  if not res then
    local err
    res, err = httpc:request_uri(url, params)
    if not res then
      return nil, err
    end
  end

  local status = res.status
  local body = res.body

  if status ~= 200 then
    if body and body ~= "" then
      debug(body)
    end
    return nil, "invalid status code received from the discovery endpoint (" .. status .. ")"
  end

  if body and body ~= "" then
    return body, nil, res.headers
  end

  return nil, "discovery endpoint did not return response body"
end


function configuration:__index(k)
  local claim = self.claims[k]
  if claim ~= nil then
    return claim
  end

  return configuration[k]
end


function configuration:discover(issuer, options)
  options = options or {}

  local body, err = configuration.load(issuer, options, self.oic.options)
  if not body then
    return nil, err
  end

  local claims, ok

  claims, err = json.decode(body)
  if not claims then
    return nil, "unable to json decode discovery response (" .. err .. ")"
  end

  if type(claims) ~= "table" then
    return nil, "invalid discovery endpoint response received"
  end

  if sub(issuer, -33) == "/.well-known/openid-configuration" then
    issuer = sub(issuer, 1, -34)

  elseif sub(issuer, -39) == "/.well-known/oauth-authorization-server" then
    issuer = sub(issuer, 1, -40)
  end

  local cis = claims.issuer
  if not cis then
    claims.issuer = issuer
  end

  local jwks_uri = claims.jwks_uri or claims.jwksUri
  if jwks_uri then
    ok, err = self.oic.keys:discover(jwks_uri, options)
    if not ok then
      return nil, err
    end
    if claims.jwks and claims.jwks.keys then
      claims.jwks.keys = nil
    end
  end

  return self:reset(claims)
end


function configuration:reset(claims)
  if type(claims) == "string" then
    local err

    claims, err = json.decode(claims)
    if not claims then
      return nil, err
    end
  end

  if type(claims) ~= "table" then
    return nil, "invalid configuration"
  end

  if claims.jwks and claims.jwks.keys then
    self.oic.keys:reset(claims.jwks.keys)
  end

  if not claims.token_introspection_endpoint and not claims.introspection_endpoint then
    local issuer = claims.issuer
    if issuer then
      if byte(issuer, -1) == SLASH then
        issuer = sub(issuer, 1, -2)
      end

      local endpoint = INTROSPECTION_ENDPOINTS[issuer]
      if endpoint then
        claims.token_introspection_endpoint = endpoint
      end
    end
  end

  self.claims = claims
  return self
end


return configuration
