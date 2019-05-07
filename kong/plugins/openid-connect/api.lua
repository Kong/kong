local endpoints = require "kong.api.endpoints"
local json = require "cjson.safe"


local escape_uri = ngx.escape_uri
local ipairs = ipairs
local kong = kong
local null = ngx.null
local fmt = string.format


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


local issuers_schema = kong.db.oic_issuers.schema


return {
  ["/openid-connect/issuers/"] = {
    schema = issuers_schema,
    methods = {
      GET = function(self, db)
        local issuers, _, err_t, offset = endpoints.page_collection(self, db, issuers_schema, "page")
        if err_t then
          return endpoints.handle_error(err_t)
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
    },
  },

  ["/openid-connect/issuers/:oic_issuers"] = {
    schema = issuers_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(issuers_schema),
      DELETE = endpoints.delete_entity_endpoint(issuers_schema),
    },
  },
}
