local endpoints = require "kong.api.endpoints"


local kong = kong
local credentials_schema = kong.db.oauth2_credentials.schema
local tokens_schema = kong.db.oauth2_tokens.schema
local consumers_schema   = kong.db.consumers.schema


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

  ["/consumers/:consumers/oauth2/"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(
              credentials_schema, consumers_schema, "consumer"),

      POST = endpoints.post_collection_endpoint(
              credentials_schema, consumers_schema, "consumer"),
    },
  },

  ["/consumers/:consumers/oauth2/:oauth2_credentials"] = {
    schema = credentials_schema,
    methods = {
      before = function(self, db)
        local consumer, _, err_t = endpoints.select_entity(self, db, consumers_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not consumer then
          return endpoints.not_found()
        end

        self.consumer = consumer

        if self.req.method ~= "PUT" then
          local cred, _, err_t = endpoints.select_entity(self, db, credentials_schema)
          if err_t then
            return endpoints.handle_error(err_t)
          end

          if not cred or cred.consumer.id ~= consumer.id then
            return endpoints.not_found()
          end

          self.oauth2_credential = cred
          self.params.oauth2_credentials = cred.id
        end
      end,
      GET  = endpoints.get_entity_endpoint(credentials_schema),
      PUT  = function(self, db, helpers)
        self.args.post.consumer = { id = self.consumer.id }
        return endpoints.put_entity_endpoint(credentials_schema)(self, db, helpers)
      end,
      PATCH  = endpoints.patch_entity_endpoint(credentials_schema),
      DELETE = endpoints.delete_entity_endpoint(credentials_schema),
    },
  },
}
