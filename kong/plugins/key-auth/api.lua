local endpoints = require "kong.api.endpoints"
local responses = require "kong.tools.responses"


local credentials_schema = kong.db.keyauth_credentials.schema
local consumers_schema   = kong.db.consumers.schema


return {
  ["/consumers/:consumers/key-auth"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(
              credentials_schema, consumers_schema, "consumer"),

      POST = endpoints.post_collection_endpoint(
              credentials_schema, consumers_schema, "consumer"),
    },
  },
  ["/consumers/:consumers/key-auth/:keyauth_credentials"] = {
    schema = credentials_schema,
    methods = {
      before = function(self, db, helpers)
        local consumer, _, err_t = endpoints.select_entity(self, db, consumers_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not consumer then
          return responses.send_HTTP_NOT_FOUND()
        end

        self.consumer = consumer

        local cred, _, err_t = endpoints.select_entity(self, db, credentials_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        if self.req.cmd_mth ~= "PUT" then
          if not cred or cred.consumer.id ~= consumer.id then
            return responses.send_HTTP_NOT_FOUND()
          end
          self.keyauth_credential = cred
          self.params.keyauth_credentials = cred.id
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
  ["/key-auths"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(credentials_schema),
    }
  },
  ["/key-auths/:keyauth_credentials/consumer"] = {
    schema = consumers_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(
              credentials_schema, consumers_schema, "consumer"),
    }
  },
}
