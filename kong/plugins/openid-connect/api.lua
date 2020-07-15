local endpoints  = require "kong.api.endpoints"
local cache      = require "kong.plugins.openid-connect.cache"
local utils      = require "kong.tools.utils"
local json       = require "cjson.safe"


local escape_uri = ngx.escape_uri
local ipairs     = ipairs
local kong       = kong
local null       = ngx.null
local fmt        = string.format


local function issuer(row)
  local configuration = row.configuration
  if configuration then
    configuration = json.decode(configuration)
    if configuration then
      row.configuration = configuration

    else
      row.configuration = {}
    end
  end

  local keys = row.keys
  if keys then
    keys = json.decode(keys)
    if keys then
      row.keys = keys

    else
      row.keys = {}
    end
  end

  row.secret = nil

  return row
end


local function filter_jwks(jwks)
  local keys = utils.deep_copy(jwks)
  for _, jwk in ipairs(keys) do
    jwk.k = nil
    jwk.d = nil
    jwk.p = nil
    jwk.q = nil
    jwk.dp = nil
    jwk.dq = nil
    jwk.qi = nil
  end

  return keys
end


local issuers_schema = kong.db.oic_issuers.schema
local jwks_schema = kong.db.oic_jwks.schema


local delete_issuer = endpoints.delete_entity_endpoint(issuers_schema)


return {
  ["/openid-connect/issuers"] = {
    schema = issuers_schema,
    methods = {
      GET = function(self, db)
        local issuers, _, err_t, offset = endpoints.page_collection(self, db, issuers_schema, "page")
        if err_t then
          return endpoints.handle_error(err_t)
        end

        if #issuers == 0 and db.strategy == "off" and cache.discovery_data then
          -- TODO: implement paging
          for i, data in ipairs(cache.discovery_data) do
            issuers[i] = utils.deep_copy(data)
          end
        end

        for i, row in ipairs(issuers) do
          issuers[i] = issuer(row)
        end

        local next_page
        if offset then
          next_page = fmt("/openid-connect/issuers?offset=%s", escape_uri(offset))
        else
          next_page = null
        end

        return kong.response.exit(200, {
          data    = issuers,
          offset  = offset,
          next    = next_page,
        })
      end,
      DELETE = function(_, db)
        if db.strategy == "off" then
          local ok, err = kong.worker_events.post("openid-connect", "purge-discovery")
          if ok ~= "done" then
            return endpoints.handle_error("failed to reset openid-connect discovery: " .. (err or ok))
          end

          ok, err = kong.worker_events.poll()
          if not ok then
            return endpoints.handle_error("failed to poll worker-events when resetting openid-connect discovery: " .. err)
          end
        end

        local ids = {}
        local count = 0
        for row, err, err_t in db.oic_issuers:each() do
          if err then
            return endpoints.handle_error(err_t or err)
          end
          count = count + 1
          ids[count] = { id = row.id }
        end

        if count > 0 then
          for i = 1, count do
            local ok, err, err_t = db.oic_issuers:delete(ids[i])
            if not ok then
              return endpoints.handle_error(err_t or err)
            end
          end
        end

        return kong.response.exit(204)
      end
    },
  },

  ["/openid-connect/issuers/:oic_issuers"] = {
    schema = issuers_schema,
    methods = {
      GET = function(self, db)
        local entity, _, err_t = endpoints.select_entity(self, db, issuers_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        if not entity and db.strategy == "off"
           and cache.discovery_data and cache.discovery_data[self.params.oic_issuers]
        then
          entity = utils.deep_copy(cache.discovery_data[self.params.oic_issuers])
        end

        if not entity then
          return kong.response.exit(404, { message = "Not found" })
        end

        return kong.response.exit(200, issuer(entity))
      end,
      DELETE = function(self, db, ...)
        if db.strategy == "off" and cache.discovery_data and cache.discovery_data[self.params.oic_issuers] then
          local ok, err = kong.worker_events.post("openid-connect", "delete-discovery", self.params.oic_issuers)
          if ok ~= "done" then
            return endpoints.handle_error("failed to reset openid-connect discovery: " .. (err or ok))
          end

          ok, err = kong.worker_events.poll()
          if not ok then
            return endpoints.handle_error("failed to poll worker-events when resetting openid-connect discovery: " .. err)
          end
        end

        return delete_issuer(self, db, ...)
      end
    },
  },

  ["/openid-connect/jwks"] = {
    schema = jwks_schema,
    methods = {
      GET = function(self, db)
        local entity, err = endpoints.select_entity(self, db, jwks_schema, "get")
        if err then
          return endpoints.handle_error(err)
        end

        if not entity then
          return kong.response.exit(404, { message = "Not found" })
        end

        return kong.response.exit(200, filter_jwks(entity.jwks), {
          ["Content-Type"] = "application/jwk-set+json",
        })
      end,
      DELETE = function(self, db)
        endpoints.delete_entity(self, db, jwks_schema, "rem")
        if err then
          return endpoints.handle_error(err)
        end

        return kong.response.exit(204)
      end,
    },
  },
}
