local cjson = require "cjson"
local utils = require "kong.tools.utils"


local setmetatable = setmetatable
local tostring = tostring
local ipairs = ipairs
local table = table
local type = type


-- Get an array of SNI names from either
-- an array(sort) or ngx.null(return {})
-- Returns an error if the list has duplicates
-- Returns nil if input is falsy.
local function parse_name_list(input, errors)
  local name_list
  if type(input) == "table" then
    name_list = utils.shallow_copy(input)

  elseif input == ngx.null then
    name_list = {}

  else
    return nil
  end

  local found = {}
  for _, name in ipairs(name_list) do
    if found[name] then
      local err_t = errors:schema_violation({
        snis = name .. " is duplicated",
      })
      return nil, tostring(err_t), err_t
    end
    found[name] = true
  end

  table.sort(name_list)
  return setmetatable(name_list, cjson.array_mt)
end


local _Certificates = {}

-- Creates a certificate
-- If the provided cert has a field called "snis" it will be used to generate server
-- names associated to the cert, after being parsed by parse_name_list.
-- Returns a certificate with the snis sorted alphabetically.
function _Certificates:insert(cert, options)
  local name_list, err, err_t = parse_name_list(cert.snis, self.errors)
  if err then
    return nil, err, err_t
  end

  if name_list then
    local ok, err, err_t = self.db.snis:check_list_is_new(name_list)
    if not ok then
      return nil, err, err_t
    end
  end

  cert.snis = nil
  cert, err, err_t = self.super.insert(self, cert, options)
  if not cert then
    return nil, err, err_t
  end

  cert.snis = name_list or cjson.empty_array

  if name_list then
    local ok, err, err_t = self.db.snis:insert_list({ id = cert.id }, name_list, options)
    if not ok then
      return nil, err, err_t
    end
  end

  return cert
end

-- Update override
-- If the cert has a "snis" attribute it will be used to update the SNIs
-- associated to the cert.
--   * If the cert had any names associated which are not on `snis`, they will be
--     removed.
--   * Any new certificates will be added to the db.
-- Returns an error if any of the new certificates where already assigned to a cert different
-- from the one identified by cert_pk
function _Certificates:update(cert_pk, cert, options)
  local name_list, err, err_t = parse_name_list(cert.snis, self.errors)
  if err then
    return nil, err, err_t
  end

  if name_list then
    local ok, err, err_t = self.db.snis:check_list_is_new(name_list, cert_pk.id)
    if not ok then
      return nil, err, err_t
    end
  end

    cert.snis = nil
    cert, err, err_t = self.super.update(self, cert_pk, cert, options)
    if err then
      return nil, err, err_t
    end

  if name_list then
    cert.snis = name_list

    local ok, err, err_t = self.db.snis:update_list(cert_pk, name_list)
    if not ok then
      return nil, err, err_t
    end

  else
    cert.snis, err, err_t = self.db.snis:list_for_certificate(cert_pk)
    if not cert.snis then
      return nil, err, err_t
    end
  end

  return cert
end

-- Upsert override
function _Certificates:upsert(cert_pk, cert, options)
  local name_list, err, err_t = parse_name_list(cert.snis, self.errors)
  if err then
    return nil, err, err_t
  end

  if name_list then
    local ok, err, err_t = self.db.snis:check_list_is_new(name_list, cert_pk.id)
    if not ok then
      return nil, err, err_t
    end
  end

  cert.snis = nil
  cert, err, err_t = self.super.upsert(self, cert_pk, cert, options)
  if err then
    return nil, err, err_t
  end

  if name_list then
    cert.snis = name_list

    local ok, err, err_t = self.db.snis:update_list(cert_pk, name_list)
    if not ok then
      return nil, err, err_t
    end

  else
    cert.snis, err, err_t = self.db.snis:list_for_certificate(cert_pk)
    if not cert.snis then
      return nil, err, err_t
    end
  end

  return cert
end


-- Returns the certificate identified by cert_pk but adds the
-- `snis` pseudo attribute to it. It is an array of strings
-- representing the SNIs associated to the certificate.
function _Certificates:select_with_name_list(cert_pk, options)
  local cert, err, err_t = self:select(cert_pk, options)
  if err_t then
    return nil, err, err_t
  end

  if not cert then
    local err_t = self.errors:not_found(cert_pk)
    return nil, tostring(err_t), err_t
  end

  cert.snis, err, err_t = self.db.snis:list_for_certificate(cert_pk)
  if err_t then
    return nil, err, err_t
  end

  return cert
end

-- Returns a page of certificates, each with the `snis` pseudo-attribute
-- associated to them. This method does N+1 queries, but for now we are limited
-- by the DAO's select options (we can't query for "all the SNIs for this
-- list of certificate ids" in one go).
function _Certificates:page(size, offset, options)
  local certs, err, err_t, offset = self.super.page(self, size, offset, options)
  if not certs then
    return nil, err, err_t
  end

  for i=1, #certs do
    local cert = certs[i]
    local snis, err, err_t = self.db.snis:list_for_certificate({ id = cert.id })
    if not snis then
      return nil, err, err_t
    end

    cert.snis = snis
  end

  return certs, nil, nil, offset
end

-- Overrides the default delete function by cascading-deleting all the SNIs
-- associated to the certificate
function _Certificates:delete(cert_pk, options)
  local name_list, err, err_t =
    self.db.snis:list_for_certificate(cert_pk)
  if not name_list then
    return nil, err, err_t
  end

  local ok, err, err_t = self.db.snis:delete_list(name_list)
  if not ok then
    return nil, err, err_t
  end

  return self.super.delete(self, cert_pk, options)
end


return _Certificates
