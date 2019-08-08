local crypto = require "kong.plugins.oauth2.crypto"
local utils = require "kong.tools.utils"


local hash_secret = function(self, cred_id_or_client_id, cred)
  -- Don't re-hash the secret digest on update, if the secret hasn't changed
  -- This causes a bug when a new secret is effectively equal the to previous
  -- digest

  local existing
  if cred_id_or_client_id then
    local err, err_t
    if utils.is_valid_uuid(cred_id_or_client_id) then
      existing, err, err_t = self:select({ id = cred_id_or_client_id })
    else
      existing, err, err_t = self:select_by_client_id(cred_id_or_client_id)
    end
    if err then
      return nil, err, err_t
    end
  end

  if existing then
    if existing.client_secret == cred.client_secret then
      return
    end
    if not cred.consumer then
      cred.consumer = existing.consumer
    end
  end

  local hashed_secret, salt = crypto.hash(cred.client_secret)
  cred.client_secret = "s256|" .. hashed_secret .. "|" .. salt

  return true
end


local _Oauth2Credentials = {}


function _Oauth2Credentials:insert(cred, options)
  local ok, err, err_t = hash_secret(self, cred.id, cred)
  if not ok then
    return nil, err, err_t
  end
  return self.super.insert(self, cred, options)
end


function _Oauth2Credentials:update(cred_pk, cred, options)
  if cred.client_secret ~= nil then
    local ok, err, err_t = hash_secret(self, cred_pk.id, cred)
    if not ok then
      return nil, err, err_t
    end
  end
  return self.super.update(self, cred_pk, cred, options)
end


function _Oauth2Credentials:update_by_client_id(client_id, cred, options)
  if cred.client_secret ~= nil then
    local ok, err, err_t = hash_secret(self, client_id, cred)
    if not ok then
      return nil, err, err_t
    end
  end
  return self.super.update_by_client_id(self, client_id, cred, options)
end


function _Oauth2Credentials:upsert(cred_pk, cred, options)
  local ok, err, err_t = hash_secret(self, cred_pk.id, cred)
  if not ok then
    return nil, err, err_t
  end
  return self.super.upsert(self, cred_pk, cred, options)
end


function _Oauth2Credentials:upsert_by_client_id(client_id, cred, options)
  local ok, err, err_t = hash_secret(self, client_id, cred)
  if not ok then
    return nil, err, err_t
  end
  return self.super.upsert_by_client_id(self, client_id, cred, options)
end


return _Oauth2Credentials

