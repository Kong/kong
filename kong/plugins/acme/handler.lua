local kong_certificate = require "kong.runloop.certificate"
local client = require "kong.plugins.acme.client"
local ngx_ssl = require "ngx.ssl"

local acme_challenge_path = [[^/\.well-known/acme-challenge/(.+)]]

-- cache for dummy cert kong generated (it's a table)
local default_cert_key

-- cache for domain mapping
local domains_matcher

local LetsencryptHandler = {}

LetsencryptHandler.PRIORITY = 999
LetsencryptHandler.VERSION = "0.2.2"

local function build_domain_matcher(domains)
  local domains_plain = {}
  local domains_wildcard = {}
  local domains_wildcard_count = 0

  if domains == nil or domains == ngx.null then
    return
  end

  for _, d in ipairs(domains) do
    if string.sub(d, 1, 1) == "*" then
      table.insert(domains_wildcard, string.sub(d, 2))
      domains_wildcard_count = domains_wildcard_count + 1
    else
      domains_plain[d] = true
    end
  end

  local domains_pattern
  if domains_wildcard_count > 0 then
    domains_pattern = "(" .. table.concat(domains_wildcard, "|") .. ")$"
  end

  domains_matcher = setmetatable(domains_plain, {
    __index = function(_, k)
      if not domains_pattern then
        return false
      end
      return ngx.re.match(k, domains_pattern, "jo")
    end
  })
end

function LetsencryptHandler:init_worker()
  local worker_id = ngx.worker.id()
  kong.log.info("acme renew timer started on worker ", worker_id)
  ngx.timer.every(86400, client.renew_certificate)
end

function LetsencryptHandler:certificate(conf)
  -- we can't check for Host header in this phase
  local host, err = ngx_ssl.server_name()
  if err then
    kong.log.warn("failed to read SNI server name: ", err)
    return
  elseif not host then
    kong.log.debug("ignoring because no SNI provided by client")
    return
  end

  -- TODO: cache me
  build_domain_matcher(conf.domains)
  if not domains_matcher or not domains_matcher[host] then
    kong.log.debug("ignoring because domain is not in whitelist")
    return
  end

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
    kong.log.debug("ignoring because non-default cert is served")
    return
  end

  local certkey, err = client.load_certkey(conf, host)
  if err then
    kong.log.warn("can't load cert and key from storage: ", err)
    return
  end

  -- cert not found, get a new one and serve default cert for now
  if not certkey then
    ngx.timer.at(0, function()
      local err = client.update_certificate(conf, host, nil)
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
    return
  end

  kong.log.debug("set certificate for host: ", host)
  local _, err
  _, err = ngx_ssl.clear_certs()
  if err then
    kong.log.warn("failed to clear certs: ", err)
  end
  _, err = ngx_ssl.set_der_cert(certkey.cert)
  if err then
    kong.log.warn("failed to set cert: ", err)
  end
  _, err = ngx_ssl.set_der_priv_key(certkey.key)
  if err then
    kong.log.warn("failed to set key: ", err)
  end
end

-- access phase is to terminate the http-01 challenge request if necessary
function LetsencryptHandler:access(conf)

  local protocol = kong.client.get_protocol()

  -- http-01 challenge only sends to http port
  if protocol == 'http' then
    local host = kong.request.get_host()
    if not host then
      return
    end

    build_domain_matcher(conf.domains)
    if not domains_matcher or not domains_matcher[kong.request.get_host()] then
      return
    end

    local captures, err =
      ngx.re.match(kong.request.get_path(), acme_challenge_path, "jo")
    if err then
      kong.log(kong.WARN, "error matching acme-challenge uri: ", err)
      return
    end

    if captures then
      -- TODO: race condition creating account?
      local err = client.create_account(conf)
      if err then
        kong.log.err("failed to create account:", err)
        return
      end

      local acme_client, err = client.new(conf)
      if err then
        kong.log.err("failed to create acme client:", err)
        return
      end

      acme_client:serve_http_challenge()
    end
    return
  end
end


return LetsencryptHandler
