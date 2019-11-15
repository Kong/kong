local BasePlugin = require("kong.plugins.base_plugin")
local kong_certificate = require("kong.runloop.certificate")

local client = require("kong.plugins.acme.client")


if kong.configuration.database == "off" then
  error("acme can't be used in Kong dbless mode currently")
end

local acme_challenge_path = [[^/\.well-known/acme-challenge/(.+)]]

-- cache for dummy cert kong generated (it's a table)
local default_cert_key

local LetsencryptHandler = BasePlugin:extend()

LetsencryptHandler.PRIORITY = 1000
LetsencryptHandler.VERSION = "0.0.1"

function LetsencryptHandler:new()
  LetsencryptHandler.super.new(self, "acme")
end

function LetsencryptHandler:init_worker()
  LetsencryptHandler.super.init_worker(self, "acme")

  kong.log.info("acme renew timer started")
  ngx.timer.every(86400, client.renew_certificate)
end


-- access phase is to terminate the http-01 challenge request if necessary
function LetsencryptHandler:access(conf)
  LetsencryptHandler.super.access(self)

  local protocol = kong.client.get_protocol()

  -- http-01 challenge only sends to http port
  if protocol == 'http' then
    local captures, err =
      ngx.re.match(kong.request.get_path(), acme_challenge_path, "jo")
    if err then
      kong.log(kong.WARN, "error matching acme-challenge uri: ", err)
      return
    end

    if captures then
      local acme_client, err = client.new(conf)

      if err then
        kong.log.err("failed to create acme client:", err)
        return
      end

      acme_client:serve_http_challenge()
    end
    return
  end

  if protocol ~= 'https' and protocol ~= 'grpcs' then
    kong.log.debug("skipping because request is protocol: ", protocol)
    return
  end

  local host = kong.request.get_host()
  -- if current request is not serving challenge, do normal proxy pass
  -- but check what cert did we used to serve request
  local cert_and_key, err = kong_certificate.find_certificate(host)
  if err then
    kong.log.err("error find certificate for current request:", err)
    return
  end

  if not default_cert_key then
    -- hack: find_certificate() returns default cert and key if no sni defined
    default_cert_key = kong_certificate.find_certificate()
  end

  -- note we compare the table address, this relies on the fact that Kong doesn't
  -- copy the default cert table around
  if cert_and_key ~= default_cert_key then
    kong.log.debug("skipping because non-default cert is served")
    return
  end

  -- TODO: do we match the whitelist?
  ngx.timer.at(0, function()
    err = client.update_certificate(conf, host, nil)
    if err then
      kong.log.err("failed to update certificate: ", err)
      return
    end
    err = client.store_renew_config(conf, host)
    if err then
      kong.log.err("failed to store renew config: ", err)
      return
    end
  end)

end


return LetsencryptHandler
