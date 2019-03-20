local endpoints = require "kong.api.endpoints"


local credentials_schema = kong.db.keyauth_credentials.schema
local kongsumers_schema   = kong.db.kongsumers.schema


local HTTP_NOT_FOUND = 404


return {
  ["/kongsumers/:kongsumers/key-auth"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(
              credentials_schema, kongsumers_schema, "kongsumer"),

      POST = endpoints.post_collection_endpoint(
              credentials_schema, kongsumers_schema, "kongsumer"),
    },
  },
  ["/kongsumers/:kongsumers/key-auth/:keyauth_credentials"] = {
    schema = credentials_schema,
    methods = {
      before = function(self, db, helpers)
        local kongsumer, _, err_t = endpoints.select_entity(self, db, kongsumers_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not kongsumer then
          return kong.response.exit(HTTP_NOT_FOUND, { message = "Not found" })
        end

        self.kongsumer = kongsumer

        if self.req.method ~= "PUT" then
          local cred, _, err_t = endpoints.select_entity(self, db, credentials_schema)
          if err_t then
            return endpoints.handle_error(err_t)
          end

          if not cred or cred.kongsumer.id ~= kongsumer.id then
            return kong.response.exit(HTTP_NOT_FOUND, { message = "Not found" })
          end
          self.keyauth_credential = cred
          self.params.keyauth_credentials = cred.id
        end
      end,

      GET  = endpoints.get_entity_endpoint(credentials_schema),
      PUT  = function(self, db, helpers)
        self.args.post.kongsumer = { id = self.kongsumer.id }
        return endpoints.put_entity_endpoint(credentials_schema)(self, db, helpers)
      end,
      PATCH  = endpoints.patch_entity_endpoint(credentials_schema),
      DELETE = endpoints.delete_entity_endpoint(credentials_schema),
    },
  },
  ["/key-auths"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(credentials_schema),
    }
  },
  ["/key-auths/:keyauth_credentials/kongsumer"] = {
    schema = kongsumers_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(
              credentials_schema, kongsumers_schema, "kongsumer"),
    }
  },
}
