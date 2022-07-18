local kong_certificate = require "kong.runloop.certificate"
local client = require "kong.plugins.acme.client"
local ngx_ssl = require "ngx.ssl"
local kong_meta = require "kong.meta"

local acme_challenge_path = [[^/\.well-known/acme-challenge/(.+)]]

-- cache for dummy cert kong generated (it's a table)
local default_cert_key

local ACMEHandler = {}

-- this has to be higher than auth plugins,
-- otherwise acme-challenges endpoints may be blocked by auth plugins
-- causing validation failures
ACMEHandler.VERSION = kong_meta.version
ACMEHandler.PRIORITY = 1705

local function build_domain_matcher(domains)
  local domains_plain = {}
  local domains_wildcard = {}
  local domains_wildcard_count = 0

  if domains == nil or domains == ngx.null then
    return false
  end

  for _, d in ipairs(domains) do
    if string.sub(d, 1, 1) == "*" then
      d = string.gsub(string.sub(d, 2), "%.", "\\.")
      table.insert(domains_wildcard, d)
      domains_wildcard_count = domains_wildcard_count + 1
    else
      domains_plain[d] = true
    end
  end

  local domains_pattern
  if domains_wildcard_count > 0 then
    domains_pattern = "(" .. table.concat(domains_wildcard, "|") .. ")$"
  end

  return setmetatable(domains_plain, {
    __index = function(_, k)
      if not domains_pattern then
        return false
      end
      return ngx.re.match(k, domains_pattern, "jo")
    end
  })
end

-- cache the domains_matcher. ACME is a global plugin.
local domains_matcher

-- expose it for use in api.lua
ACMEHandler.build_domain_matcher = build_domain_matcher

function ACMEHandler:init_worker()
  local worker_id = ngx.worker.id()
  kong.log.info("acme renew timer started on worker ", worker_id)
  ngx.timer.every(86400, client.renew_certificate)

  -- handle cache updating of domains_matcher
  kong.worker_events.register(function(data)
    if data.entity.name ~= "acme" then
      return
    end

    local operation = data.operation

    if operation == "create" or operation == "update" then
      local conf = data.entity.config
      domains_matcher = build_domain_matcher(conf.domains)
    end


  end, "crud", "plugins")
end

local function check_domains(conf, host)
  if conf.allow_any_domain then
    return true
  end

  -- create the cache at first usage
  if domains_matcher == nil then
    domains_matcher = build_domain_matcher(conf.domains)
  end

  return domains_matcher and domains_matcher[host]
end

function ACMEHandler:certificate(conf)
  -- we can't check for Host header in this phase
  local host, err = ngx_ssl.server_name()
  if err then
    kong.log.warn("failed to read SNI server name: ", err)
    return
  elseif not host then
    kong.log.debug("ignoring because no SNI provided by client")
    return
  end

  host = string.lower(host)

  if not check_domains(conf, host) then
    kong.log.debug("ignoring because domain is not in allowed-list: ", host)
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

  local certkey, err = client.load_certkey_cached(conf, host)
  if err then
    kong.log.warn("can't load cert and key from storage: ", err)
    return
  end

  -- cert not found, get a new one and serve default cert for now
  if not certkey then
    if kong.configuration.role == "data_plane" and conf.storage == "kong" then
      kong.log.err("creating new certificate through proxy side with ",
                    "\"kong\" storage in Hybrid mode is not supported; ",
                    "consider create certificate using Admin API or ",
                    "use other external storages")
      return
    end

    ngx.timer.at(0, function()
      local ok, err = client.update_certificate(conf, host, nil)
      if err then
        kong.log.err("failed to update certificate: ", err)
        return
      end
      -- if not ok and err is nil, meaning the update is running by another worker
      if ok then
        err = client.store_renew_config(conf, host)
        if err then
          kong.log.err("failed to store renew config: ", err)
          return
        end
      end
    end)
    return
  end

  -- this will only be run in dbless
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
function ACMEHandler:access(conf)

  local protocol = kong.client.get_protocol()

  -- http-01 challenge only sends to http port
  if protocol == 'http' then
    local host = kong.request.get_host()
    if not host then
      return
    end

    if not check_domains(conf, host) then
      -- We do not log here because it would flood the log
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


return ACMEHandler
