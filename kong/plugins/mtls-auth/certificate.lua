--- Copyright 2019 Kong Inc.
local build_ssl_route_filter_set = require("kong.plugins.mtls-auth.filter").build_ssl_route_filter_set
local ngx_ssl = require "ngx.ssl"
local server_name = ngx_ssl.server_name


local SNI_CACHE_KEY = "mtls-auth:cert_enabled_snis"
local TTL_FOREVER = { ttl = 0 }


local _M = {}


local kong = kong


function _M.execute()
  local snis_set, err = kong.cache:get(SNI_CACHE_KEY, TTL_FOREVER,
          build_ssl_route_filter_set)

  if err then
    kong.log.err("unable to request client to present its certificate: ",
            err)
    return ngx.exit(ngx.ERROR)
  end

  local server_name = server_name()

  if snis_set["*"] or (server_name and snis_set[server_name])  then
    -- TODO: improve detection of ennoblement once we have DAO functions
    -- to filter plugin configurations based on plugin name

    kong.log.debug("enabled, will request certificate from client")

    local res, err = kong.client.tls.request_client_certificate()
    if not res then
      kong.log.err("unable to request client to present its certificate: ",
                     err)
    end

    -- disable session resumption to prevent inability to access client
    -- certificate in later phases
    res, err = kong.client.tls.disable_session_reuse()
    if not res then
      kong.log.err("unable to disable session reuse for client certificate: ",
                     err)
    end
  end
end


return _M
