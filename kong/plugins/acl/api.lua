local endpoints = require "kong.api.endpoints"


local kong             = kong
local acls_schema      = kong.db.acls.schema
local consumers_schema = kong.db.consumers.schema


return {
  ["/consumers/:consumers/acls/"] = {
    schema = acls_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(
              acls_schema, consumers_schema, "consumer"),
      POST = endpoints.post_collection_endpoint(
              acls_schema, consumers_schema, "consumer"),
    },
  },

  ["/consumers/:consumers/acls/:acls"] = {
    schema = acls_schema,
    methods = {
      before = function(self, db, helpers)
        local consumer, _, err_t = endpoints.select_entity(self, db, consumers_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not consumer then
          return kong.response.exit(404, { message = "Not found" })
        end

        self.consumer = consumer

        local acl, _, err_t = endpoints.select_entity(self, db, acls_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        if self.req.cmd_mth ~= "PUT" then
          if not acl or acl.consumer.id ~= consumer.id then
            return kong.response.exit(404, { message = "Not found" })
          end
          self.acl = acl
          self.params.acls = acl.id
        end
      end,
      GET  = endpoints.get_entity_endpoint(acls_schema),
      PUT  = function(self, db, helpers)
        self.args.post.consumer = { id = self.consumer.id }
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
  ["/acls/:acls/consumer"] = {
    schema = consumers_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(
              acls_schema, consumers_schema, "consumer"),
    }
  }
}
