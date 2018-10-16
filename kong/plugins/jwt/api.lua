local endpoints = require "kong.api.endpoints"
local responses = require "kong.tools.responses"


local jwt_secrets_schema = kong.db.jwt_secrets.schema
local consumers_schema   = kong.db.consumers.schema


return {
  ["/consumers/:consumers/jwt/"] = {
    schema = jwt_secrets_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(
              jwt_secrets_schema, consumers_schema, "consumer"),

      POST = endpoints.post_collection_endpoint(
              jwt_secrets_schema, consumers_schema, "consumer"),
    }
  },

  ["/consumers/:consumers/jwt/:jwt_secrets"] = {
    schema = jwt_secrets_schema,
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

        local cred, _, err_t = endpoints.select_entity(self, db, jwt_secrets_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        if self.req.cmd_mth ~= "PUT" then
          if not cred or cred.consumer.id ~= consumer.id then
            return responses.send_HTTP_NOT_FOUND()
          end
          self.keyauth_credential = cred
          self.params.keyauth_jwt_secrets = cred.id
        end
      end,
      GET  = endpoints.get_entity_endpoint(jwt_secrets_schema),
      PUT  = function(self, db, helpers)
        self.args.post.consumer = { id = self.consumer.id }
        return endpoints.put_entity_endpoint(jwt_secrets_schema)(self, db, helpers)
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
  ["/jwts/:jwt_secrets/consumer"] = {
    schema = consumers_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(
              jwt_secrets_schema, consumers_schema, "consumer"),
    }
  }
}
