local endpoints = require "kong.api.endpoints"


local kong             = kong
local acls_schema      = kong.db.acls.schema
local kongsumers_schema = kong.db.kongsumers.schema


return {
  ["/kongsumers/:kongsumers/acls/"] = {
    schema = acls_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(
              acls_schema, kongsumers_schema, "kongsumer"),
      POST = endpoints.post_collection_endpoint(
              acls_schema, kongsumers_schema, "kongsumer"),
    },
  },

  ["/kongsumers/:kongsumers/acls/:acls"] = {
    schema = acls_schema,
    methods = {
      before = function(self, db, helpers)
        local kongsumer, _, err_t = endpoints.select_entity(self, db, kongsumers_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not kongsumer then
          return kong.response.exit(404, { message = "Not found" })
        end

        self.kongsumer = kongsumer

        if self.req.method ~= "PUT" then
          local acl, _, err_t = endpoints.select_entity(self, db, acls_schema)
          if err_t then
            return endpoints.handle_error(err_t)
          end

          if not acl or acl.kongsumer.id ~= kongsumer.id then
            return kong.response.exit(404, { message = "Not found" })
          end

          self.acl = acl
          self.params.acls = acl.id
        end
      end,
      GET  = endpoints.get_entity_endpoint(acls_schema),
      PUT  = function(self, db, helpers)
        self.args.post.kongsumer = { id = self.kongsumer.id }
        return endpoints.put_entity_endpoint(acls_schema)(self, db, helpers)
      end,
      PATCH  = endpoints.patch_entity_endpoint(acls_schema),
      DELETE = endpoints.delete_entity_endpoint(acls_schema),
    },
  },
  ["/acls"] = {
    schema = acls_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(acls_schema),
    }
  },
  ["/acls/:acls/kongsumer"] = {
    schema = kongsumers_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(
              acls_schema, kongsumers_schema, "kongsumer"),
    }
  }
}
