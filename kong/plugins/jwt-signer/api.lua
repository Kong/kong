local cache = require "kong.plugins.jwt-signer.cache"
local endpoints = require "kong.api.endpoints"
local json  = require "cjson.safe"


local escape_uri = ngx.escape_uri
local fmt = string.format
local setmetatable = setmetatable
local ipairs = ipairs
local kong = kong
local null = ngx.null
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


local jwks_schema = kong.db.jwt_signer_jwks.schema


return {
  ["/jwt-signer/jwks"] = {
    schema = jwks_schema,
    methods = {
      GET = function(self, db)
        -- TODO: Remove hardcoded method "page" once 4f90ae61c gets on ee
        local jwks, _, err_t, offset = endpoints.page_collection(self, db, jwks_schema, "page")

        if err_t then
          return endpoints.handle_error(err_t)
        end
        for i, row in ipairs(jwks) do
          jwks[i] = post_process_keys(row)
        end

        local next_page
        if offset then
          next_page = fmt("jwt-signer/jwks?offset=%s", escape_uri(offset))
        else
          next_page = null
        end

        return kong.response.exit(200, {
          data      = jwks,
          offset    = offset,
          next      = next_page,
        })
      end,
    },
  },

  ["/jwt-signer/jwks/:jwt_signer_jwks"] = {
    schema = jwks_schema,
    methods = {
      GET = function(self, db)
        local row, _, err = endpoints.select_entity(self, db, jwks_schema)
        if err then
          return endpoints.handle_error(err)
        elseif row == nil then
          return kong.response.exit(404, { message = "Not found" })
        end

        return kong.response.exit(200, post_process_row(row))
      end,
      DELETE = endpoints.delete_entity_endpoint(jwks_schema),
    },
  },

  ["/jwt-signer/jwks/:jwt_signer_jwks/rotate"] = {
    schema = jwks_schema,
    methods = {
      POST = function(self, db)
        local row, _, err = endpoints.select_entity(self, db, jwks_schema)
        if err then
          return endpoints.handle_error(err)
        elseif row == nil then
          return kong.response.exit(404, { message = "Not found" })
        end

        local ok

        ok, err = cache.rotate_keys(row.name, row, true, true)
        if not ok then return endpoints.handle_error(err) end

        row, _, err = endpoints.select_entity(self, db, jwks_schema)
        if err then
          return endpoints.handle_error(err)
        elseif row == nil then
          return kong.response.exit(404, { message = "Not found" })
        end

        return kong.response.exit(200, post_process_row(row))
      end,
    },
  },
}
