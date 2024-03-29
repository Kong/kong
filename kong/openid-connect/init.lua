-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http          = require "resty.http"
local configuration = require "kong.openid-connect.configuration"
local authorization = require "kong.openid-connect.authorization"
local globaloptions = require "kong.openid-connect.options"
local issuer        = require "kong.openid-connect.issuer"
local client        = require "kong.openid-connect.client"
local token         = require "kong.openid-connect.token"
local codec         = require "kong.openid-connect.codec"
local debug         = require "kong.openid-connect.debug"
local keys          = require "kong.openid-connect.keys"
local jwt           = require "kong.openid-connect.jwt"


local decode_args   = ngx.decode_args
local setmetatable  = setmetatable
local tonumber      = tonumber
local tostring      = tostring
local json          = codec.json
local base64        = codec.base64
local base64url     = codec.base64url
local type          = type
local byte          = string.byte
local sub           = string.sub


local SLASH = byte("/")


local USERINFO = {
  ["https://www.paypal.com"] = function(tok, query)
    query = query or {}
    if type(query) ~= "table" then
      query = decode_args(tostring(query), 0)
    end

    if not query.schema then
      query.schema = "openid"
    end

    if not query.access_token then
      query.access_token = tok
    end

    return tok, query, nil
  end
}


local oic = {}


oic.__index = oic


function oic.new(opts, config, jwks)
  local self         = setmetatable({}, oic)
  self.configuration = configuration.new(self, config)
  self.authorization = authorization.new(self)
  self.options       = globaloptions.new(self, opts or {})
  self.issuer        = issuer.new(self)
  self.client        = client.new(self)
  self.token         = token.new(self)
  self.keys          = keys.new(self, jwks)
  self.jwt           = jwt.new(self)

  if not opts then
    return self
  end

  if opts.subject then
    local ok, err = self:discover(opts.subject)
    if not ok then
      return nil, err
    end
  end

  if opts.issuer then
    local ok, err = self.issuer:discover(opts.issuer)
    if not ok then
      return nil, err
    end
  end

  -- TODO: Add support for registration(?)
  -- if opts.registration_access_token then
  -- end

  return self
end


function oic:discover(subject, params)
  local iss = self.issuer:webfinger(subject, params)
  return self.issuer:discover(iss or subject, params)
end


function oic:userinfo(tok, options)
  options = options or {}

  local opts = self.options
  local conf = self.configuration

  local endpoint = options.userinfo_endpoint or
                      opts.userinfo_endpoint or
                      conf.userinfo_endpoint

  if not endpoint then
    return nil, "userinfo endpoint was not specified"
  end

  local headers = options.headers or opts.headers or {}

  local query = options.query or {}

  local iss = conf.issuer
  if iss then
    if byte(iss, -1) == SLASH then
      iss = sub(iss, 1, -2)
    end

    if USERINFO[iss] then
      tok, query, headers = USERINFO[iss](tok, query, headers)
    end
  end

  headers["Authorization"] = "Bearer " .. tok

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
    query      = query,
    method     = "GET",
    headers    = headers,
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

  local res = httpc:request_uri(endpoint, params)
  if not res then
    local err
    res, err = httpc:request_uri(endpoint, params)
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
    return nil, "invalid status code received from the userinfo endpoint (" .. status .. ")"
  end

  if body and body ~= "" then
    local userinfo_format = options.userinfo_format or opts.userinfo_format or nil
    if userinfo_format == "string" then
      return body, nil, res.headers

    elseif userinfo_format == "base64" then
      return base64.encode(body), nil, res.headers

    elseif userinfo_format == "base64url" then
      return base64url.encode(body), nil, res.headers

    else
      local userinfo, err = json.decode(body)
      if not userinfo then
        return nil, "unable to json decode userinfo response (" .. err .. ")"
      end

      if type(userinfo) ~= "table" then
        return nil, "invalid userinfo endpoint response received from the userinfo endpoint"
      end

      return userinfo, nil, res.headers
    end
  end

  return nil, "userinfo endpoint did not return response body"
end


function oic:reset(opts, claims, jwks)
  if opts then
    self.options:reset(opts)
  end
  self.issuer:reset(claims, jwks)
end


return oic
