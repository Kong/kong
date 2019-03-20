local endpoints = require "kong.api.endpoints"


local kong = kong
local jwt_secrets_schema = kong.db.jwt_secrets.schema
local kongsumers_schema   = kong.db.kongsumers.schema


return {
  ["/kongsumers/:kongsumers/jwt/"] = {
    schema = jwt_secrets_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(jwt_secrets_schema, kongsumers_schema,
                                              "kongsumer"),
      POST = endpoints.post_collection_endpoint(jwt_secrets_schema, kongsumers_schema,
                                                "kongsumer"),
    }
  },
  ["/kongsumers/:kongsumers/jwt/:jwt_secrets"] = {
    schema = jwt_secrets_schema,
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
          local cred, _, err_t = endpoints.select_entity(self, db, jwt_secrets_schema)
          if err_t then
            return endpoints.handle_error(err_t)
          end

          if not cred or cred.kongsumer.id ~= kongsumer.id then
            return kong.response.exit(404, { message = "Not found" })
          end

          self.keyauth_credential = cred
          self.params.keyauth_jwt_secrets = cred.id
        end
      end,
      GET  = endpoints.get_entity_endpoint(jwt_secrets_schema),
      PUT  = function(self, ...)
        self.args.post.kongsumer = { id = self.kongsumer.id }
        return endpoints.put_entity_endpoint(jwt_secrets_schema)(self, ...)
      end,
      PATCH  = endpoints.patch_entity_endpoint(jwt_secrets_schema),
      DELETE = endpoints.delete_entity_endpoint(jwt_secrets_schema),
    },
  },
  ["/jwts/"] = {
    schema = jwt_secrets_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(jwt_secrets_schema),
    }
  },
  ["/jwts/:jwt_secrets/kongsumer"] = {
    schema = kongsumers_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(jwt_secrets_schema, kongsumers_schema,
                                          "kongsumer"),
    }
  }
}
