-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Copyright 2019 Kong Inc.
local ngx_ssl = require "ngx.ssl"
local ssl_clt = require "ngx.ssl.clienthello"
local sni_filter = require("kong.tls.plugins.sni_filter")
local pl_stringx = require "pl.stringx"
local server_name = ngx_ssl.server_name
local PREFIX_SNIS_PSEUDO_INDEX = sni_filter.PREFIX_SNIS_PSEUDO_INDEX
local POSTFIX_SNIS_PSEUDO_INDEX = sni_filter.POSTFIX_SNIS_PSEUDO_INDEX
local startswith = pl_stringx.startswith
local endswith = pl_stringx.endswith

local _M = {}

local kong = kong
local EMPTY_T = {}


local function match_sni(snis, server_name)
  if server_name then
    -- search plain snis
    if snis[server_name] then
      kong.log.debug("matched the plain sni ", server_name)
      return snis[server_name]
    end

    -- TODO: use radix tree to accelerate the search once we have an available implementation
    -- search snis with the leftmost wildcard
    for sni, sni_t in pairs(snis[POSTFIX_SNIS_PSEUDO_INDEX] or EMPTY_T) do
      if endswith(server_name, sni_t.value) then
        kong.log.debug(server_name, " matched the sni with the leftmost wildcard ", sni)
        return sni_t
      end
    end

    -- search snis with the rightmost wildcard
    for sni, sni_t in pairs(snis[PREFIX_SNIS_PSEUDO_INDEX] or EMPTY_T) do
      if startswith(server_name, sni_t.value) then
        kong.log.debug(server_name, " matched the sni with the rightmost wildcard ", sni)
        return sni_t
      end
    end
  end

  if server_name then
    kong.log.debug("client sent an unknown sni ", server_name)

  else
    kong.log.debug("client didn't send an sni")
  end

  if snis["*"] then
    kong.log.debug("mTLS is enabled globally")
    return snis["*"]
  end
end

function _M.execute(snis_set)

  local server_name = server_name()

  local sni_mapping = match_sni(snis_set, server_name)

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

function _M.execute_client_hello(snis_set, options)
  if not snis_set then
    return
  end

  if not options then
    return
  end

  if not options.disable_http2 then
    return
  end

  local server_name, err = ssl_clt.get_client_hello_server_name()
  if err then
    kong.log.debug("unable to get client hello server name: ", err)
    return
  end

  local sni_mapping = match_sni(snis_set, server_name)

  if sni_mapping  then
    local res, err = kong.client.tls.disable_http2_alpn()
    if not res then
      kong.log.err("unable to disable http2 alpn: ", err)
    end
  end
end

return _M
