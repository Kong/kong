local endpoints = require "kong.api.endpoints"


local HTTP_NOT_FOUND = 404


local kong = kong
local credentials_schema = kong.db.oauth2_credentials.schema
local tokens_schema = kong.db.oauth2_tokens.schema
local kongsumers_schema   = kong.db.kongsumers.schema


return {
  ["/oauth2_tokens/"] = {
    schema = tokens_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(tokens_schema),
      POST = endpoints.post_collection_endpoint(tokens_schema),
    },
  },

  ["/oauth2_tokens/:token_or_id"] = {
    schema = tokens_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(tokens_schema),
      PUT = endpoints.put_entity_endpoint(tokens_schema),
      PATCH = endpoints.patch_entity_endpoint(tokens_schema),
      DELETE = endpoints.delete_entity_endpoint(tokens_schema),
    },
  },

  ["/oauth2/"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(credentials_schema),
    }
  },

  ["/kongsumers/:kongsumers/oauth2/"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(
              credentials_schema, kongsumers_schema, "kongsumer"),

      POST = endpoints.post_collection_endpoint(
              credentials_schema, kongsumers_schema, "kongsumer"),
    },
  },

  ["/kongsumers/:kongsumers/oauth2/:oauth2_credentials"] = {
    schema = credentials_schema,
    methods = {
      before = function(self, db)
        local kongsumer, _, err_t = endpoints.select_entity(self, db, kongsumers_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not kongsumer then
          return kong.response.exit(HTTP_NOT_FOUND, { message = "Not Found" })
        end

        self.kongsumer = kongsumer

        if self.req.method ~= "PUT" then
          local cred, _, err_t = endpoints.select_entity(self, db, credentials_schema)
          if err_t then
            return endpoints.handle_error(err_t)
          end

          if not cred or cred.kongsumer.id ~= kongsumer.id then
            return kong.response.exit(HTTP_NOT_FOUND, { message = "Not Found" })
          end
          self.oauth2_credential = cred
          self.params.oauth2_credentials = cred.id
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
}
