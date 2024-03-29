-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http         = require "resty.http"
local uri          = require "kong.openid-connect.uri"
local codec        = require "kong.openid-connect.codec"
local debug        = require "kong.openid-connect.debug"


local setmetatable = setmetatable
local tonumber     = tonumber
local ipairs       = ipairs
local type         = type
local json         = codec.json
local sub          = string.sub


local issuer = {}


issuer.__index = issuer


function issuer.new(oic)
  return setmetatable({ oic = oic }, issuer)
end


function issuer:webfinger(subject, options)
  options = options or {}

  local url, res, jrd, err

  if sub(subject, -22) ~= "/.well-known/webfinger" then
    url, err = uri.webfinger(subject)
    if not url then
      return nil, err
    end
  end

  local opts = self.oic.options

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

  res = httpc:request_uri(url, params)
  if not res then
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
    return nil, "invalid status code received from the webfinger endpoint (" .. status .. ")"
  end

  if body and body ~= "" then
    jrd, err = json.decode(body)
    if not jrd then
      return nil, "unable to json decode webfinger endpoint response (" .. err .. ")"
    end

    if type(jrd) ~= "table" then
      return nil, "invalid webfinger endpoint response received"
    end

    if jrd.links then
      for _, link in ipairs(jrd.links) do
        if link.rel == "http://openid.net/specs/connect/1.0/issuer" then
          if sub(link.href, 1, 8) ~=  "https://" then
            return nil, "invalid issuer scheme"
          end

          return link.href, nil, res.headers, jrd
        end
      end
    end

    return nil, "issuer was not found"
  end

  return nil, "webfinger endpoint did not return response body"
end


function issuer:discover(iss, options)
  local url, err = uri.discover(iss)
  if not url then
    return nil, err
  end

  return self.oic.configuration:discover(url, options)
end


function issuer:reset(claims, jwks)
  if claims then
    self.oic.configuration:reset(claims)
  end
  if jwks then
    self.oic.keys:reset(jwks)
  end
end


return issuer
