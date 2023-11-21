-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Copyright 2019-2020 Kong Inc.
local _M = {}


local resty_kong_tls = require("resty.kong.tls")
local openssl_x509 = require("resty.openssl.x509")
local openssl_x509_chain = require("resty.openssl.x509.chain")
local openssl_x509_store = require("resty.openssl.x509.store")
local mtls_cache = require("kong.plugins.mtls-auth.cache")
local ocsp_client = require("kong.plugins.mtls-auth.ocsp_client")
local crl_client = require("kong.plugins.mtls-auth.crl_client")
local constants = require("kong.constants")


local kong = kong
local ngx = ngx
local ngx_re_gmatch = ngx.re.gmatch
local ipairs = ipairs
local pairs = pairs
local new_tab = require("table.new")
local tb_concat = table.concat
local table_concat = table.concat
local ngx_var = ngx.var
local sha256_hex = require "kong.tools.utils".sha256_hex
local flag_partial_chain = openssl_x509_store.verify_flags.X509_V_FLAG_PARTIAL_CHAIN


local cache_opts = {
  l1_serializer = function(cas)
    local trust_store, err = openssl_x509_store.new()
    if err then
      return nil, err
    end
    local reverse_lookup = new_tab(0, #cas)

    for _, ca in ipairs(cas) do
      local x509, err = openssl_x509.new(ca.cert,"PEM")
      if err then
        return nil, err
      end

      local _
      _, err = trust_store:add(x509)
      if err then
        return nil, err
      end

      local digest
      digest, err = x509:digest()
      if err then
        return nil, err
      end

      reverse_lookup[digest] = ca.id
    end

    return {
      store = trust_store,
      reverse_lookup = reverse_lookup,
    }
  end,
  ttl = 3600,
  neg_ttl = 3600,
}


local function load_cas(ca_ids)
  kong.log.debug("cache miss for CA store")

  local cas = new_tab(#ca_ids, 0)
  local key = new_tab(1, 0)

  for i, ca_id in ipairs(ca_ids) do
    key.id = ca_id

    local obj, err = kong.db.ca_certificates:select(key)
    if not obj then
      if err then
        return nil, err
      end

      return nil, "CA Certificate '" .. tostring(ca_id) .. "' does not exist"
    end

    cas[i] = obj
  end

  return cas
end


local function load_credential(cache_key)
  local cred, err = kong.db.mtls_auth_credentials
                    :select_by_cache_key(cache_key)
  if not cred then
    return nil, err
  end

  return cred
end


local function find_credential(subject_name, ca_id, ttl)
  local opts = {
    ttl = ttl,
    neg_ttl = ttl,
  }

  local credential_cache_key = kong.db.mtls_auth_credentials
                               :cache_key(subject_name, ca_id)
  local credential, err = kong.cache:get(credential_cache_key, opts,
                                         load_credential, credential_cache_key)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if credential then
    return credential
  end

  -- try wildcard match
  credential_cache_key = kong.db.mtls_auth_credentials
                         :cache_key(subject_name, nil)
  kong.log.debug("cache key is: ", credential_cache_key)
  credential, err = kong.cache:get(credential_cache_key, nil, load_credential,
                                   credential_cache_key)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  return credential
end


local function load_consumer(consumer_field, value)
  local result, err
  local dao = kong.db.consumers

  if consumer_field == "id" then
    result, err = dao:select({ id = value })

  else
     result, err = dao["select_by_" .. consumer_field](dao, value)
  end

  if err then
    return nil, err
  end

  return result
end


local function find_consumer(value, consumer_by, ttl)

  local opts = {
    ttl = ttl,
    neg_ttl = ttl,
  }

  for _, field_name in ipairs(consumer_by) do
    local key, consumer, err

    if field_name == "id" then
      key = kong.db.consumers:cache_key(value)

    else
      key = mtls_cache.consumer_field_cache_key(field_name, value)
    end

    consumer, err = kong.cache:get(key, opts, load_consumer, field_name,
                                   value)

    if err then
      kong.log.err(err)
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    if consumer then
      return consumer
    end
  end

  return nil
end


local set_header = kong.service.request.set_header
local function set_consumer(consumer, credential)
  local clear_header = kong.service.request.clear_header

  if consumer and consumer.id then
    set_header(constants.HEADERS.CONSUMER_ID, consumer.id)

  else
    clear_header(constants.HEADERS.CONSUMER_ID)
  end

  if consumer and consumer.custom_id then
    set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)

  else
    clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
  end

  if consumer and consumer.username then
    set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)

  else
    clear_header(constants.HEADERS.CONSUMER_USERNAME)
  end

  kong.client.authenticate(consumer, credential)

  if credential then
    if credential.username then
      set_header(constants.HEADERS.CREDENTIAL_IDENTIFIER, credential.username)

    else
      clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
    end

    clear_header(constants.HEADERS.ANONYMOUS)

  else
    clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
    set_header(constants.HEADERS.ANONYMOUS, true)
  end
end


local function parse_fullchain(pem)
  return ngx_re_gmatch(pem,
                      "-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----",
                      "jos")
end


local function get_subject_names_from_cert(x509)
  -- per RFC 6125, check subject alternate names first
  -- before falling back to common name

  local names = new_tab(4, 0)
  local names_n = 0
  local cn

  local subj_alt, _ = x509:get_subject_alt_name()

  if subj_alt then
    for _, val in pairs(subj_alt) do
      names_n = names_n + 1
      names[names_n] = val
    end
  end

  local subj, err = x509:get_subject_name()
  if err then
    return nil, nil, err
  end

  if subj then
    local entry, _
    entry, _, err = subj:find("CN")
    if err then
      return nil, nil, err
    end
    if entry then
      names_n = names_n + 1
      names[names_n] = entry.blob
      cn = entry.blob
    end
  end

  return names, cn
end


local function ca_ids_cache_key(ca_ids)
  return sha256_hex("mtls:cas:" .. tb_concat(ca_ids, ':'))
end

local authenticate_group_by = {
  ["DN"] = function(cn)
    local group = {
      ngx_var.ssl_client_s_dn
    }
    return group
  end,
  ["CN"] = function(cn)
    if not cn then
      return nil, "Certificate missing Common Name"
    end

    local group = {
      cn
    }
    return group
  end,
}


local function set_cert_headers(names)
  set_header("X-Client-Cert-DN", ngx_var.ssl_client_s_dn)

  if #names ~= 0 then
    set_header("X-Client-Cert-SAN", table_concat(names, ","))
  end
end


local function is_cert_revoked(conf, proof_chain, store)
  kong.log.debug("cache miss for revocation status")

  local ocsp_status, err = ocsp_client.validate_cert(conf, proof_chain)
  if err then
    kong.log.warn("OCSP verify: ", err)
  end
  -- URI set and no communication error
  if ocsp_status ~= nil then
    return not ocsp_status
  end

  -- no OCSP URI set, check for CRL
  local crl_status
  crl_status, err = crl_client.validate_cert(conf, proof_chain, store)
  if err then
    kong.log.warn("CRL verify: ", err)
  end

  -- URI set and no communication error
  if crl_status ~= nil then
    return not crl_status
  end

  -- returns an error string so that mlcache won't cache the value
  return nil, "fail to check revocation"
end


local function do_authentication(conf)
  local pem, err = resty_kong_tls.get_full_client_certificate_chain()
  if err then
    if err == "connection is not TLS or TLS support for Nginx not enabled" then
      -- request is cleartext, no certificate can possibly be present
      return nil, "No required TLS certificate was sent"
    end

    kong.log.err(err)
    return kong.response.exit(500, "An unexpected error occurred")
  end

  if not pem then
    -- client failed to provide certificate while handshaking
    ngx.ctx.CLIENT_VERIFY_OVERRIDE = "NONE"
    return nil, "No required TLS certificate was sent"
  end

  local chain = new_tab(2, 0)
  local it

  it, err = parse_fullchain(pem)
  if not it then
    kong.log.err(err)
    return kong.response.exit(500, "An unexpected error occurred")
  end

  local chain_n = 0

  while true do
    local m, err = it()
    if err then
      kong.log.err(err)
      return kong.response.exit(500, "An unexpected error occurred")
    end

    if not m then
      -- no match found (any more)
      break
    end

    chain_n = chain_n + 1
    chain[chain_n] = m[0]
  end

  local intermidiate
  if #chain > 1 then
    intermidiate, err = openssl_x509_chain.new()
    if err then
      kong.log.err(err)
      return kong.response.exit(500, "An unexpected error occurred")
    end
  end

  for i, c in ipairs(chain) do
    local x509
    x509, err = openssl_x509.new(c, "PEM")
    if err then
      kong.log.err(err)
      return kong.response.exit(500, "An unexpected error occurred")
    end
    chain[i] = x509

    if i > 1 then
      local _
      _, err = intermidiate:add(x509)
      if err then
        kong.log.err(err)
        return kong.response.exit(500, "An unexpected error occurred")
      end
    end
  end

  local ca_ids = conf.ca_certificates

  local cache_key, trust_table
  cache_key, err = ca_ids_cache_key(ca_ids)
  if not err then
    trust_table, err = kong.cache:get(cache_key, cache_opts, load_cas, ca_ids)
  end

  if err or not trust_table then
    kong.log.err(err)
    return kong.response.exit(500, "An unexpected error occurred")
  end

  local flags
  if conf.allow_partial_chain then
    flags = flag_partial_chain
  end

  local proof_chain
  proof_chain, err = trust_table.store:verify(chain[1], intermidiate, true, nil, nil, flags)
  if proof_chain then
    -- get the matching CA id
    local ca = proof_chain[#proof_chain]

    local digest
    digest, err = ca:digest()
    if err then
      return nil, err
    end

    local ca_id = trust_table.reverse_lookup[digest]

    local names, cn
    names, cn, err = get_subject_names_from_cert(chain[1])
    if err then
      return nil, err
    end
    kong.log.debug("names = ", tb_concat(names, ", "))

    -- revocation check
    if conf.revocation_check_mode ~= "SKIP" then
      local revoked
      revoked, err = kong.cache:get(ngx_var.ssl_client_s_dn,
        { ttl = conf.cert_cache_ttl }, is_cert_revoked,
        conf, proof_chain, trust_table.store)
      if err then
        if conf.revocation_check_mode == "IGNORE_CA_ERROR" and
          err:find("fail to check revocation", nil, true) then
          kong.log.notice(err .. ". Ignored this as `revocation_check_mode` is `IGNORE_CA_ERROR`.")
        else
          kong.log.err(err)
        end
      end

      -- there was communication error or neither of OCSP URI or CRL URI set
      if revoked == nil then
        if conf.revocation_check_mode == "IGNORE_CA_ERROR" then
          revoked = false
        else
          revoked = true
        end
      end

      if revoked == true then
        ngx.ctx.CLIENT_VERIFY_OVERRIDE = "FAILED:certificate revoked"
        return nil, "TLS certificate failed verification"
      end
    end

    if conf.skip_consumer_lookup then
      if conf.authenticated_group_by then
        local group
        group, err = authenticate_group_by[conf.authenticated_group_by](cn)
        if not group then
          return nil, err
        end

        ngx.ctx.authenticated_groups = group
      end
      set_cert_headers(names)
      return true
    end

    for _, n in ipairs(names) do
      local credential = find_credential(n, ca_id, conf.cache_ttl)
      if credential then
        local consumer = find_consumer(credential.consumer.id, { "id", },
                                       conf.cache_ttl)

        if consumer then
          set_consumer(consumer, { id = consumer.id, })
          return true
        end
      end
    end

    kong.log.debug("unable to match certificate to consumers via credentials")

    local consumer_by = conf.consumer_by

    if consumer_by and #consumer_by > 0 then
      kong.log.debug("auto matching")

      for _, n in ipairs(names) do
        local consumer = find_consumer(n, conf.consumer_by,
                                       conf.cache_ttl)

        if consumer then
          set_consumer(consumer, { id = consumer.id, })
          return true
        end
     end
    end

    kong.log.warn("certificate is valid but consumer matching failed, ",
                  "using cn = ", cn,
                  " fields = ", tb_concat(consumer_by, ", "))
    ngx.ctx.CLIENT_VERIFY_OVERRIDE = "FAILED:consumer not found"
  end

  kong.log.err("client certificate verify failed: ", (err and err or "UNKNOWN"))
  ngx.ctx.CLIENT_VERIFY_OVERRIDE = "FAILED:" .. (err and err or "UNKNOWN")

  return nil, "TLS certificate failed verification"
end


function _M.execute(conf)
  if conf.anonymous and kong.client.get_credential() then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local res, message = do_authentication(conf)
  if not res then
    -- failed authentication
    if conf.anonymous then
      local consumer_cache_key = kong.db.consumers:cache_key(conf.anonymous)
      local consumer, err = kong.cache:get(consumer_cache_key, nil,
                                                kong.client.load_consumer,
                                                conf.anonymous, true)

      if err then
        kong.log.err(err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      set_consumer(consumer, nil)

    else
      return kong.response.exit(401, { message = message })
    end

  else
    ngx.ctx.CLIENT_VERIFY_OVERRIDE = "SUCCESS"
  end
end


return _M
