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
local getmetatable = getmetatable
local tonumber     = tonumber
local ipairs       = ipairs
local json         = codec.json
local base64url    = codec.base64url
local type         = type


local keys = {}


local function decode_jwks(jwks)
  if type(jwks) == "string" then
    local err

    jwks, err = json.decode(jwks)
    if not jwks then
      return nil, err
    end
  end

  if type(jwks) ~= "table" then
    return nil, "invalid jwks"
  end

  if jwks.keys then
    jwks = jwks.keys
  end

  if type(jwks) == "string" then
    local err

    jwks, err = json.decode(jwks)
    if not jwks then
      return nil, err
    end
  end

  return jwks
end


function keys.new(settings, jwks, jwks_previous)
  settings = settings or {}

  local default
  if settings.options and settings.options.enable_hs_signatures then
    local secret = settings.options.client_secret
    if type(secret) == "string" and #secret > 0 then
      default = { k = base64url.encode(secret) }
    end
  end

  local self = setmetatable({
    settings      = settings,
    jwks_uri      = settings.jwks_uri,
    jwks          = {},
    jwks_previous = {},
    kids          = {},
    x5ts          = {},
    algs          = {},
    comp          = {},
    comp2         = {},
    default       = default,
  }, keys)
  if jwks then
    self:reset(jwks, jwks_previous)
  end
  return self
end


function keys.load(url, options, opts)
  if not url then
    return nil, "jwks uri was not specified"
  end

  options = options or {}
  opts    = opts    or {}

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

  local ssl_client_cert, ssl_client_priv_key
  -- ssl_client_cert and ssl_client_priv_key are already cdata.
  if options.ssl_client_cert and options.ssl_client_priv_key then
    ssl_client_cert = options.ssl_client_cert
    ssl_client_priv_key = options.ssl_client_priv_key

  elseif opts.ssl_client_cert and opts.ssl_client_priv_key then
    ssl_client_cert = opts.ssl_client_cert
    ssl_client_priv_key = opts.ssl_client_priv_key
  end

  local params = {
    version    = tonumber(options.http_version) or tonumber(opts.http_version),
    query      = options.query,
    headers    = options.headers,
    body       = options.body,
    keepalive  = keepalive,
    ssl_verify = ssl_verify,
    ssl_client_cert     = ssl_client_cert,
    ssl_client_priv_key = ssl_client_priv_key,
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
    return nil, "invalid status code received from the jwks endpoint (" .. status .. ")"
  end

  if body and body ~= "" then
    local jwks, err = json.decode(body)
    if not jwks then
      return nil, "unable to json decode jwks endpoint response (" .. err .. ")"
    end

    if type(jwks) ~= "table" then
      return nil, "invalid jwks endpoint response received"
    end

    if options.unwrap == true then
      jwks = jwks.keys
    end

    if options.json ~= false then
      jwks, err = json.encode(jwks)
      if not jwks then
        return nil, "unable to json encode jwks (" .. err .. ")"
      end
    end

    return jwks, nil, res.headers
  end

  return nil, "jwks endpoint did not return response body"
end


function keys:__index(k)
  if type(k) == "number" then
    return self.jwks[k]
  end

  local jwk = self.comp[k]
  if jwk ~= nil then
   return jwk
  end

  jwk = self.comp2[k]
  if jwk ~= nil then
   return jwk
  end

  jwk = self.kids[k]
  if jwk ~= nil then
   return jwk
  end

  jwk = self.x5ts[k]
  if jwk ~= nil then
   return jwk
  end

  jwk = self.algs[k]
  if jwk ~= nil then
    return jwk
  end

  return keys[k]
end


function keys:discover(url, options)
  options = options or {}

  self.jwks_uri = url or self.jwks_uri
  self.options  = options

  local jwks
  local body, err = keys.load(self.jwks_uri, self.options, self.settings.options)
  if not body then
    return nil, err
  end

  jwks, err = json.decode(body)
  if not keys then
    return nil, "unable to json decode keys (" .. err .. ")"
  end

  return self:reset(jwks.keys)
end


function keys:rediscover(options)
  if options and type(options.rediscover_keys) == "function" then
    return self:reset(options.rediscover_keys())

  elseif self.options and type(self.options.rediscover_keys) == "function" then
    return self:reset(self.options.rediscover_keys())

  elseif self.settings.options and type(self.settings.options.rediscover_keys) == "function" then
    return self:reset(self.settings.options.rediscover_keys())
  end

  if not self.jwks_uri and self.settings.configuration then
      self.jwks_uri = self.settings.configuration.jwks_uri or
                      self.settings.configuration.jwksUri
  end

  return self:discover(self.jwks_uri, options or self.options)
end


function keys:reset(jwks, jwks_previous)
  if getmetatable(jwks) == keys then
    return jwks
  end

  local err

  jwks, err = decode_jwks(jwks)
  if err then
    return nil, err
  end

  if jwks_previous then
    jwks_previous, err = decode_jwks(jwks_previous)
    if err then
      return nil, err
    end
  end

  self.kids = {}
  self.x5ts = {}
  self.algs = {}
  self.comp = {}
  self.comp2 = {}
  self.jwks = jwks or {}
  self.jwks_previous = jwks_previous or {}

  for i, k in ipairs(self.jwks) do
    if type(k) == "table" then
      if k.kid and not self.kids[k.kid] then
        self.kids[k.kid] = self.jwks[i]
      end

      if k.x5t and not self.x5ts[k.x5t] and k.x5t ~= k.kid then
        self.x5ts[k.x5t] = self.jwks[i]
      end

      if k.alg and not self.algs[k.alg] then
        self.algs[k.alg] = self.jwks[i]
      end

      if k.kid and k.alg then
        local ckey = k.kid .. ":" .. k.alg
        if not self.comp[ckey] then
          self.comp[ckey] = self.jwks[i]
        end
      end

      if k.x5t and k.alg and k.x5t ~= k.kid then
        local ckey = k.x5t .. ":" .. k.alg
        if not self.comp2[ckey] then
          self.comp2[ckey] = self.jwks[i]
        end
      end
    end
  end

  for i, k in ipairs(self.jwks_previous) do
    if type(k) == "table" then
      if k.kid and not self.kids[k.kid] then
        self.kids[k.kid] = self.jwks_previous[i]
      end

      if k.x5t and not self.algs[k.x5t] and k.x5t ~= k.kid then
        self.x5ts[k.x5t] = self.jwks_previous[i]
      end

      if k.alg and not self.algs[k.alg] then
        self.algs[k.alg] = self.jwks_previous[i]
      end

      if k.kid and k.alg then
        local ckey = k.kid .. ":" .. k.alg
        if not self.comp[ckey] then
          self.comp[ckey] = self.jwks_previous[i]
        end
      end

      if k.x5t and k.alg and k.x5t ~= k.kid then
        local ckey = k.x5t .. ":" .. k.alg
        if not self.comp2[ckey] then
          self.comp2[ckey] = self.jwks_previous[i]
        end
      end
    end
  end

  return self
end


return keys
