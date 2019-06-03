--- Copyright 2019 Kong Inc.


local _M = {}


local resty_kong_tls = require("resty.kong.tls")
local ngx_re = require("ngx.re")
local openssl_x509 = require("openssl.x509")
local openssl_x509_chain = require("openssl.x509.chain")
local openssl_x509_store = require("openssl.x509.store")
local mtls_cache = require("kong.plugins.mtls-auth.cache")
local constants = require("kong.constants")


local kong = kong
local ngx_exit = ngx.exit
local ngx_ERROR = ngx.ERROR
local ngx_re_gmatch = ngx.re.gmatch
local ipairs = ipairs
local pairs = pairs
local new_tab = require("table.new")
local tb_concat = table.concat
local ngx_md5 = ngx.md5
local null = ngx.null
local cache_opts = {
  l1_serializer = function(cas)
    local trust_store = openssl_x509_store.new()
    local reverse_lookup = new_tab(0, #cas)

    for _, ca in ipairs(cas) do
      local x509 = openssl_x509.new(ca.cert, "PEM")
      trust_store:add(x509)

      reverse_lookup[x509:digest()] = ca.id
    end

    return {
      store = trust_store,
      reverse_lookup = reverse_lookup,
    }
  end,
}


local function load_cas(ca_ids)
  kong.log.debug("cache miss for CA store")

  local cas = new_tab(#ca_ids, 0)
  local key = new_tab(1, 0)

  for i, ca_id in ipairs(ca_ids) do
    key.id = ca_id

    local obj, err = kong.db.certificates:select(key)
    if not obj then
      return nil, err
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
                         :cache_key(subject_name, null)
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


local function set_consumer(consumer, credential)
  local set_header = kong.service.request.set_header
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
      set_header(constants.HEADERS.CREDENTIAL_USERNAME, credential.username)

    else
      clear_header(constants.HEADERS.CREDENTIAL_USERNAME)
    end

    clear_header(constants.HEADERS.ANONYMOUS)

  else
    clear_header(constants.HEADERS.CREDENTIAL_USERNAME)
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

  local names = new_tab(1, 0)
  local names_n = 0

  local subj_alt = x509:getSubjectAlt()

  for t, val in pairs(subj_alt) do
    names_n = names_n + 1
    names[names_n] = val
  end

  local subj = x509:getSubject()

  for _, entry in ipairs(subj:all()) do
    if entry.id == "2.5.4.3" then -- common name
      names_n = names_n + 1
      names[names_n] = entry.blob
    end
  end

  return names
end


local function ca_ids_cache_key(ca_ids)
    return ngx_md5("mtls:cas:" .. tb_concat(ca_ids, ':'))
end


local function do_authentication(conf)
  local pem, err = resty_kong_tls.get_full_client_certificate_chain()
  if err then
    if err == "connection is not TLS or TLS support for Nginx not enabled" then
      -- request is cleartext, no certificate can possibly be present
      return nil, 496, "No required TLS certificate was sent"
    end

    kong.log.err(err)
    return kong.response.exit(500, "An unexpected error occurred")
  end

  if not pem then
    -- client failed to provide certificate while handshaking
    return nil, 496, "No required TLS certificate was sent"
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

  local intermidiate = #chain > 1 and openssl_x509_chain.new() or nil

  for i, c in ipairs(chain) do
    local x509 = openssl_x509.new(c, "PEM")
    chain[i] = x509

    if i > 1 then
      intermidiate:add(x509)
    end
  end

  local ca_ids = conf.certificate_authorities

  local trust_table, err = kong.cache:get(ca_ids_cache_key(ca_ids), cache_opts,
                                          load_cas, ca_ids)
  if not trust_table then
    kong.log.err(err)
    return kong.response.exit(500, "An unexpected error occurred")
  end

  local res, chain_or_err = trust_table.store:verify(chain[1], intermidiate)
  if res then
    -- get the matching CA id

    local ca
    for _, obj in ipairs(chain_or_err) do
      ca = obj
    end

    local ca_id = trust_table.reverse_lookup[ca:digest()]

    local names = get_subject_names_from_cert(chain[1])
    kong.log.debug("names = ", tb_concat(names, ", "))

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
  end

  kong.log.err(chain_or_err)

  return nil, 495, "TLS certificate failed verification"
end


local function load_consumer_into_memory(consumer_id, anonymous)
  local result, err = kong.db.consumers:select({ id = consumer_id })
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "' .. consumer_id .. '" not found'
    end

    return nil, err
  end

  return result
end


function _M.execute(conf)
  if conf.anonymous and kong.client.get_credential() then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local res, status, message = do_authentication(conf)
  if not res then
    -- failed authentication
    if conf.anonymous then
      local consumer, err = find_consumer(conf.anonymous, { 'id', },
                                          conf.cache_ttl)
      if err then
        kong.log.err(err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      set_consumer(consumer, nil)

    else
      return kong.response.exit(status, { message = message })
    end
  end
end


return _M
