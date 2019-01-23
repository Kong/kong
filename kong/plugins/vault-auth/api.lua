local endpoints = require "kong.api.endpoints"
local http = require "resty.http"
local cjson = require "cjson"
local vault_lib = require "kong.plugins.vault-auth.vault"
local utils = require "kong.tools.utils"


local Schema = require "kong.db.schema"
local vault_credentials_schema = Schema.new(require"kong.plugins.vault-auth.vault-daos")


local function broadcast_invalidation(access_token)
  kong.cache:invalidate("vault-auth:" .. access_token)
end


local function insert_vault_cred(vault_t, args)
  local vault = vault_lib.new(vault_t)

  local ok, err = vault:post(args.access_token, args)
  if not ok then
    return nil, err
  end

  broadcast_invalidation(args.access_token)

  return args
end


local function fetch_vault_cred(vault_t, access_token)
  local vault = vault_lib.new(vault_t)

  local cred, err = vault:fetch(access_token)
  if err then
    kong.log.err("Error fetching Vault credential: ", err)
    return kong.response.exit(err == "not found" and 404 or 500)
  end

  return kong.response.exit(200, { data = cred })
end


local function list_vault_creds(vault_t)
  local vault = vault_lib.new(vault_t)

  local data, err = vault:list()
  if err then
    kong.log.err("Error listing Vault credentials: ", err)
    return kong.response.exit(err == "not found" and 404 or 500)
  end

  local keys = {}
  for _, key in ipairs(data.keys) do
    table.insert(keys, vault:fetch(key))
  end

  return kong.response.exit(200, { data = keys })
end


local function delete_vault_cred(vault_t, access_token)
  local vault = vault_lib.new(vault_t)

  local ok, err = vault:delete(access_token)
  if not ok then
    kong.log.err("Error deleting Vault credential: ", err)
    return kong.response.exit(err == "not found" and 404 or 500)
  end

  broadcast_invalidation(access_token)

  return kong.response.exit(204)
end


local function upsert_secret(self, db, helpers, context)
  local entity = vault_credentials_schema:process_auto_fields(self.params, context)

  local ok, err = vault_credentials_schema:validate(entity)
  if not ok then
    kong.log.err(err)
    return kong.response.exit(500, err)
  end

  local cred, err = insert_vault_cred(self.vault, entity)
  if not cred then
    kong.log.err("Error upserting Vault credential: ", err)
    return kong.response.exit(err == "not found" and 404 or 500)
  end

  return kong.response.exit(201, { data = entity })
end


local function find_entity(dao, key, endpoint_key)
  if not endpoint_key then
    endpoint_key = "name"
  end

  if type(key) == "table" and next(key) then
    _, key = next(key)
  end

  if utils.is_valid_uuid(key) then
    return dao:select({ id = key })
  else
    return dao["select_by_" .. endpoint_key](dao, key)
  end
end


return {
  ["/vaults/:vault/credentials"] = {
    before = function(self, db, helpers)
      local vault, _, err_t = find_entity(kong.db.vaults, self.params.vault)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not vault then
        return kong.response.exit(404, { message = "Vault instance not found" })
      end

      self.vault = vault
      self.params.vault = nil

      if self.req.cmd_mth == "GET" then
        return
      end

      if not self.params.consumer then
        return kong.response.exit(400, { message = "No consumer provided" })
      end

      local consumer, _, err_t = find_entity(kong.db.consumers,
                                             self.params.consumer, "username")
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not consumer then
        return kong.response.exit(404, { message = "Consumer not found" })
      end
    end,

    GET = function(self, db, helpers)
      return list_vault_creds(self.vault)
    end,

    POST = function(self, db, helpers)
      return upsert_secret(self, db, helpers, "insert")
    end,
  },

  ["/vaults/:vault/credentials/:consumer"] = {
    before = function(self, db, helpers)
      local vault, _, err_t = find_entity(kong.db.vaults, self.params.vault)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not vault then
        return kong.response.exit(404, { message = "Vault instance not found" })
      end

      self.vault = vault
      self.params.vault = nil

      if not self.params.consumer then
        return kong.response.exit(400, { message = "No consumer provided" })
      end

      local consumer, _, err_t = find_entity(kong.db.consumers,
                                             self.params.consumer, "username")
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not consumer then
        return kong.response.exit(404, { message = "Consumer not found" })
      end

      self.params.consumer = { id = consumer.id }
    end,

    POST = function(self, db, helpers)
      return upsert_secret(self, db, helpers, "insert")
    end,
  },

  ["/vaults/:vault/credentials/token/:access_token"] = {
    before = function(self, db, helpers)
      local vault, _, err_t = find_entity(kong.db.vaults, self.params.vault)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not vault then
        return kong.response.exit(404, { message = "Vault instance not found" })
      end

      self.vault = vault
      self.params.vault = nil
    end,

    GET = function(self, db, helpers)
      return fetch_vault_cred(self.vault, self.params.access_token)
    end,

    DELETE = function(self, db, helpers)
      return delete_vault_cred(self.vault, self.params.access_token)
    end
  },
}
