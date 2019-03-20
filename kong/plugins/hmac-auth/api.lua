local endpoints = require "kong.api.endpoints"


local kong               = kong
local credentials_schema = kong.db.hmacauth_credentials.schema
local kongsumers_schema   = kong.db.kongsumers.schema


return{
  ["/kongsumers/:kongsumers/hmac-auth"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(
              credentials_schema, kongsumers_schema, "kongsumer"),

      POST = endpoints.post_collection_endpoint(
              credentials_schema, kongsumers_schema, "kongsumer"),
    }
  },

  ["/kongsumers/:kongsumers/hmac-auth/:hmacauth_credentials"] = {
    schema = credentials_schema,
    methods = {
      before = function(self, db)
        local kongsumer, _, err_t = endpoints.select_entity(self, db, kongsumers_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not kongsumer then
          return kong.response.exit(404, { message = "Not found" })
        end

        self.kongsumer = kongsumer

        if self.req.method ~= "PUT" then
          local cred, _, err_t = endpoints.select_entity(self, db, credentials_schema)
          if err_t then
            return endpoints.handle_error(err_t)
          end

          if not cred or cred.kongsumer.id ~= kongsumer.id then
            return kong.response.exit(404, { message = "Not found" })
          end

          self.hmacauth_credential = cred
          self.params.hmacauth_credentials = cred.id
        end
      end,
      GET  = endpoints.get_entity_endpoint(credentials_schema),
      PUT  = function(self, ...)
        self.args.post.kongsumer = { id = self.kongsumer.id }
        return endpoints.put_entity_endpoint(credentials_schema)(self, ...)
      end,
      PATCH  = endpoints.patch_entity_endpoint(credentials_schema),
      DELETE = endpoints.delete_entity_endpoint(credentials_schema),
    },
  },
  ["/hmac-auths/"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(credentials_schema),
    }
  },
  ["/hmac-auths/:hmacauth_credentials/kongsumer"] = {
    schema = kongsumers_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(
              credentials_schema, kongsumers_schema, "kongsumer"),
    }
  },
}
