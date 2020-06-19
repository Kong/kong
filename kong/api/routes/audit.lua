local endpoints = require "kong.api.endpoints"


local kong = kong
local escape_uri = ngx.escape_uri
local null = ngx.null
local fmt = string.format


if not kong.configuration.audit_log then
  return {}
end



-- Copy of `kong.api.endpoints.get_collection_endpoint`
-- Needed as the endpoint name differs from the entity's schema
local function get_collection_endpoint(schema, next_page_prefix)

  return function(self, db, helpers)
    local args = self.args.uri
    local opts = endpoints.extract_options(args, schema, "select")
    local size, err = endpoints.get_page_size(args)
    if err then
      return endpoints.handle_error(db[schema.name].errors:invalid_size(err))
    end

    local data, _, err_t, offset = db[schema.name]:page(size, args.offset, opts)
    if err_t then
      return endpoints.handle_error(err_t)
    end

    local next_page = offset and fmt("/%s?offset=%s",
                                     next_page_prefix,
                                     escape_uri(offset))
                              or null

    return kong.response.exit(200, {
      data   = data,
      offset = offset,
      next   = next_page,
    })
  end
end

return {
  ["/audit/requests"] = {
    schema = kong.db.audit_requests.schema,
    methods = {
      GET = get_collection_endpoint(kong.db.audit_requests.schema,
                                    "audit/requests"),
    }
  },

  ["/audit/objects"] = {
    schema = kong.db.audit_requests.schema,
    methods = {
      GET = get_collection_endpoint(kong.db.audit_objects.schema,
                                    "audit/objects"),
    }
  },
}
