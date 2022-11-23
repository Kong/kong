-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Copyright 2019 Kong Inc.
local ngx_ssl = require "ngx.ssl"
local server_name = ngx_ssl.server_name

local _M = {}

local kong = kong

function _M.execute(snis_set)

  local server_name = server_name()

  local sni_mapping = (server_name and snis_set[server_name]) or snis_set["*"]

  if sni_mapping  then
    -- TODO: improve detection of ennoblement once we have DAO functions
    -- to filter plugin configurations based on plugin name

    kong.log.debug("enabled, will request certificate from client")

    local chain
    -- send CA DN list
    if sni_mapping.ca_cert_chain then
      kong.log.debug("set client ca certificate chain")
      chain = sni_mapping.ca_cert_chain.ctx
    end

    local res, err = kong.client.tls.request_client_certificate(chain)
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
