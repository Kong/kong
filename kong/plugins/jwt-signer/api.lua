local cache = require "kong.plugins.jwt-signer.cache"
local utils = require "kong.tools.utils"
local crud  = require "kong.api.crud_helpers"
local json  = require "cjson.safe"


local setmetatable = setmetatable
local ipairs = ipairs
local pairs = pairs
local type = type


local EMPTY_ARRAY = setmetatable({}, json.empty_array_mt)
local PRIVATE = {
  d = true,
  p = true,
  q = true,
  dp = true,
  dq = true,
  qi = true,
  oth = true,
}


local function clear_private_keys(jwks)
  if type(jwks) == "table" then
    for _, jwk in ipairs(jwks) do
      if type(jwk) == "table" then
        for key in pairs(jwk) do
          if PRIVATE[key] then
            jwk[key] = nil
          end
        end
      end
    end

  else
    return EMPTY_ARRAY
  end

  return jwks
end


local function decode_jwks(row, key)
  local jwks = row[key]
  if jwks then
    if type(jwks) == "string" then
      jwks = json.decode(jwks)
      if jwks then
        row[key] = clear_private_keys(jwks)

      else
        row[key] = EMPTY_ARRAY
      end

    elseif type(jwks) == "table" then
      row[key] = clear_private_keys(jwks)
    else
      row[key] = EMPTY_ARRAY
    end

  else
    row[key] = EMPTY_ARRAY
  end
end


local function post_process_keys(row)
  if type(row) == "table" then
    decode_jwks(row, "keys")
    decode_jwks(row, "previous")
  end

  return row
end


local function post_process_row(row)
  row.id = nil
  row.name = nil
  row.created_at = nil
  row.updated_at = nil

  return post_process_keys(row)
end


return {
  ["/jwt-signer/jwks/"] = {
    resource = "jwt-signer",

    GET = function(self, dao)
      crud.paginated_set(self, dao.jwt_signer_jwks, post_process_keys)
    end,
  },

  ["/jwt-signer/jwks/:id"] = {
    resource = "jwt-signer",

    GET = function(self, dao, helpers)
      local id = self.params.id

      local row, err
      if utils.is_valid_uuid(id) then
        row, err = dao.jwt_signer_jwks:find({ id = id })

      else
        row, err = dao.jwt_signer_jwks:find_all({ name = id })
        row = row and row[1]
      end

      if err then
        return helpers.yield_error(err)
      elseif row == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return helpers.responses.send_HTTP_OK(post_process_row(row))
    end,

    DELETE = function(self, dao, helpers)
      local id = self.params.id

      if utils.is_valid_uuid(id) then
        return crud.delete({ id = self.params.id }, dao.jwt_signer_jwks)
      end

      local row, err = dao.jwt_signer_jwks:find_all({ name = id })
      row = row and row[1]

      if err then
        return helpers.yield_error(err)
      elseif row == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return crud.delete({ id = row.id }, dao.jwt_signer_jwks)
    end
  },

  ["/jwt-signer/jwks/:id/rotate"] = {
    resource = "jwt-signer",

    POST = function(self, dao, helpers)
      local id = self.params.id

      local row, err
      if utils.is_valid_uuid(id) then
        row, err = dao.jwt_signer_jwks:find({ id = id })

      else
        row, err = dao.jwt_signer_jwks:find_all({ name = id })
        row = row and row[1]
      end

      if err then
        return helpers.yield_error(err)

      elseif row == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local ok

      ok, err = cache.rotate_keys(row.name, row, true, true)
      if not ok then
        return helpers.yield_error(err)
      end

      row, err = dao.jwt_signer_jwks:find({ id = row.id })
      if err then
        return helpers.yield_error(err)

      elseif row == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return helpers.responses.send_HTTP_OK(post_process_row(row))
    end,
  },
}
