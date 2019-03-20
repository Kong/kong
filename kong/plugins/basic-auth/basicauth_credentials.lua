local crypto = require "kong.plugins.basic-auth.crypto"
local utils = require "kong.tools.utils"


local hash_password = function(self, cred_id_or_username, cred)
  -- Don't re-hash the password digest on update, if the password hasn't changed
  -- This causes a bug when a new password is effectively equal the to previous digest
  local existing
  if cred_id_or_username then
    local err, err_t
    if utils.is_valid_uuid(cred_id_or_username) then
      existing, err, err_t = self:select({ id = cred_id_or_username })
    else
      existing, err, err_t = self:select_by_username(cred_id_or_username)
    end
    if err then
      return nil, err, err_t
    end
  end

  if existing then
    if existing.password == cred.password then
      return
    end
    if not cred.kongsumer then
      cred.kongsumer = existing.kongsumer
    end
  end

  cred.password = crypto.hash(cred.kongsumer.id, cred.password)

  return true
end


local _BasicauthCredentials = {}


function _BasicauthCredentials:insert(cred, options)
  local ok, err, err_t = hash_password(self, cred.id, cred)
  if not ok then
    return nil, err, err_t
  end
  return self.super.insert(self, cred, options)
end


function _BasicauthCredentials:update(cred_pk, cred, options)
  local ok, err, err_t = hash_password(self, cred_pk.id, cred)
  if not ok then
    return nil, err, err_t
  end
  return self.super.update(self, cred_pk, cred, options)
end


function _BasicauthCredentials:update_by_username(username, cred, options)
  local ok, err, err_t = hash_password(self, username, cred)
  if not ok then
    return nil, err, err_t
  end
  return self.super.update_by_username(self, username, cred, options)
end


function _BasicauthCredentials:upsert(cred_pk, cred, options)
  local ok, err, err_t = hash_password(self, cred_pk.id, cred)
  if not ok then
    return nil, err, err_t
  end
  return self.super.upsert(self, cred_pk, cred, options)
end


function _BasicauthCredentials:upsert_by_username(username, cred, options)
  local ok, err, err_t = hash_password(self, username, cred)
  if not ok then
    return nil, err, err_t
  end
  return self.super.upsert_by_username(self, username, cred, options)
end


return _BasicauthCredentials
