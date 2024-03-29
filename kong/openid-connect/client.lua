-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http         = require "resty.http"
local set          = require "kong.openid-connect.set"
local codec        = require "kong.openid-connect.codec"
local nyi          = require "kong.openid-connect.nyi"


local setmetatable = setmetatable
local decode_args  = codec.args.decode
local tonumber     = tonumber
local type         = type


local client = {}


client.__index = client


function client.new(oic)
  return setmetatable({ oic = oic }, client)
end


function client:register(data, options)
  options = options or {}

  local opts = self.oic.options
  local conf = self.oic.configuration

  local registration_endpoint = options.registration_endpoint or
                                   opts.registration_endpoint or
                                   conf.registration_endpoint
  if not registration_endpoint then
    return nil, "registration endpoint was not found"
  end

  local args = options.args or opts.args or {}
  if type(args) == "string" then
    args = decode_args(args)
  end
  if type(args) ~= "table" then
    return nil, "invalid arguments"
  end

  local redirect_uris, count = set.new(options.redirect_uris or opts.redirect_uris)
  if count == 0 then
    return nil, "redirect uris were not specified"
  end
  args.redirect_uris = redirect_uris

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

  -- TODO: actual post request
  return nyi(data, params)
end


function client:discover()
  return nyi(self)
end


return client
