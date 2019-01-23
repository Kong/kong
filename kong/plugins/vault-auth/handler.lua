local constants = require "kong.constants"
local BasePlugin = require "kong.plugins.base_plugin"
local http = require "resty.http"
local cjson = require "cjson.safe"
local vault_lib = require "kong.plugins.vault-auth.vault"


local kong = kong
local type = type


local _realm = 'Key realm="' .. _KONG._NAME .. '"'


local VaultAuthHandler = BasePlugin:extend()


VaultAuthHandler.PRIORITY = 1003
VaultAuthHandler.VERSION = "1.0.0"


function VaultAuthHandler:new()
  VaultAuthHandler.super.new(self, "vault-auth")
end


local validate_vault_cred
do
  local Schema = require "kong.db.schema"
  local vault_credentials_schema = Schema.new(require"kong.plugins.vault-auth.vault-daos")

  validate_vault_cred = function(data)
    local entity = vault_credentials_schema:process_auto_fields(data, "select")

    local ok, err = vault_credentials_schema:validate(entity)
    if not ok then
      return nil, err
    end

    return entity
  end
end


local function load_credential(access_token, conf)
  local vault_t, err = kong.db.vaults:select(conf.vault)
  if err then
    error("error fetching Vault: ", err)
  end
  if not vault_t then
    error("invalid Vault object association")
  end

  local vault = vault_lib.new(vault_t)

  local data, err = vault:fetch(access_token)
  if err and err ~= "not found" then
    error("error fetching credential: " .. err)
  end

  if not data then
    return nil
  end

  local cred, err = validate_vault_cred(data)
  if not cred then
    error("error validating credential data from Vault: " .. err)
  end

  if cred.ttl and not tonumber(cred.ttl) then
    ngx.log(ngx.WARN, "Invalid TTL in credential '", tostring(cred.ttl), "'")
  end

  return cred, nil, cred.ttl
end


local function load_consumer(consumer_id, anonymous)
  local result, err = kong.db.consumers:select({ id = consumer_id })
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "' .. consumer_id .. '" not found'
    end

    return nil, err
  end

  return result
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


local function find_token(t, conf, headers, query, body)
  local name = conf[t .. "_token_name"]

  local token = headers[name]
  if not token then
    token = query[name]
  end

  if conf.hide_credentials then
    query[name] = nil
    kong.service.request.set_query(query)
    kong.service.request.clear_header(name)
  end

  if not conf.tokens_in_body then
    return token
  end

  if conf.hide_credentials then
    body[name] = nil
    kong.service.request.set_body(body)
  end

  return body[name]
end


local function do_authentication(conf)
  local headers = kong.request.get_headers()
  local query = kong.request.get_query()
  local body

  -- read in the body if we want to examine POST args
  if conf.tokens_in_body then
    local err
    body, err = kong.request.get_body()

    if err then
      kong.log.err("Cannot process request body: ", err)
      return nil, { status = 400, message = "Cannot process request body" }
    end
  end

  local access_token = find_token("access", conf, headers, query, body)
  if not access_token then
    return nil, { status = 401, message = "No access token found" }
  end
  local secret_token = find_token("secret", conf, headers, query, body)
  if not secret_token then
    return nil, { status = 401, message = "No secret token found" }
  end

  -- retrieve our consumer linked to this API key

  local cache = kong.cache

  local credential_cache_key = "vault-auth:" .. access_token
  local credential, err = cache:get(credential_cache_key, nil, load_credential,
                                    access_token, conf)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, "An unexpected error occurred")
  end

  -- no credential in Vault, for this key, it is invalid, HTTP 401
  if not credential then
    return nil, { status = 401, message = "Invalid authentication credentials" }
  end

  if credential.secret_token ~= secret_token then
    return nil, { status = 401, message = "Invalid secret token" }
  end

  -----------------------------------------
  -- Success, this request is authenticated
  -----------------------------------------

  -- retrieve the consumer linked to this API key, to set appropriate headers
  local consumer_cache_key, consumer
  consumer_cache_key = kong.db.consumers:cache_key(credential.consumer.id)
  consumer, err      = cache:get(consumer_cache_key, nil, load_consumer,
                                 credential.consumer.id)
  if err then
    kong.log.err(err)
    return nil, { status = 500, message = "An unexpected error occurred" }
  end

  set_consumer(consumer, credential)

  return true
end


function VaultAuthHandler:access(conf)
  VaultAuthHandler.super.access(self)

  -- check if preflight request and whether it should be authenticated
  if not conf.run_on_preflight and kong.request.get_method() == "OPTIONS" then
    return
  end

  if conf.anonymous and kong.client.get_credential() then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous then
      -- get anonymous user
      local consumer_cache_key = kong.db.consumers:cache_key(conf.anonymous)
      local consumer, err = kong.cache:get(consumer_cache_key, nil,
                                           load_consumer, conf.anonymous, true)
      if err then
        kong.log.err(err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      set_consumer(consumer, nil)

    else
      return kong.response.exit(err.status, { message = err.message }, err.headers)
    end
  end
end


return VaultAuthHandler
