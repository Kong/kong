local endpoints = require "kong.api.endpoints"
local to_hex = require "resty.string".to_hex
local http = require "resty.http"
local meta = require "kong.plugins.basic-auth.meta"


local kong               = kong
local credentials_schema = kong.db.basicauth_credentials.schema
local consumers_schema   = kong.db.consumers.schema


-- verify is a password sent via the Admin API is present in the
-- haveibeenpwned.com passwords data set
local function been_pwned(password)
  local sha = string.upper(to_hex(ngx.sha1_bin(password)))
  local r = sha:sub(1, 5)
  local suffix = sha:sub(6)

  local c = http.new()
  local res, err = c:request_uri(meta.HIBP_URL .. r, {
    ssl_verify = false,
  })
  if err then
    return nil, err
  end

  if res.status ~= 200 then
    return nil, "invalid response code " .. res.status
  end

  return string.find(res.body, suffix, nil, true) and true or false
end


return {
  ["/consumers/:consumers/basic-auth"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(
              credentials_schema, consumers_schema, "consumer"),

      POST = function(self, ...)
        local pwned, err = been_pwned(self.args.post.password)
        if err then
          return kong.response.exit(500, { message = err })
        end
        if pwned then
          return kong.response.exit(400, { message = "PWNED!" })
        end

        return endpoints.post_collection_endpoint(
              credentials_schema, consumers_schema, "consumer")(self, ...)
      end,
    },
  },
  ["/consumers/:consumers/basic-auth/:basicauth_credentials"] = {
    schema = credentials_schema,
    methods = {
      before = function(self, db)
        local consumer, _, err_t = endpoints.select_entity(self, db, consumers_schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not consumer then
          return kong.response.exit(404, { message = "Not found" })
        end

        self.consumer = consumer

        if self.req.method ~= "PUT" then
          local cred, _, err_t = endpoints.select_entity(self, db, credentials_schema)
          if err_t then
            return endpoints.handle_error(err_t)
          end

          if not cred or cred.consumer.id ~= consumer.id then
            return kong.response.exit(404, { message = "Not found" })
          end

          self.basicauth_credential = cred
          self.params.basicauth_credentials = cred.id
        end
      end,

      GET  = endpoints.get_entity_endpoint(credentials_schema),
      PUT  = function(self, ...)
        self.args.post.consumer = { id = self.consumer.id }

        local pwned, err = been_pwned(self.args.post.password)
        if err then
          return kong.response.exit(500, { message = err })
        end
        if pwned then
          return kong.response.exit(400, { message = "PWNED!" })
        end

        return endpoints.put_entity_endpoint(credentials_schema)(self, ...)
      end,
      PATCH  = function(self, ...)
        local pwned, err = been_pwned(self.args.post.password)
        if err then
          return kong.response.exit(500, { message = err })
        end
        if pwned then
          return kong.response.exit(400, { message = "PWNED!" })
        end

        return endpoints.patch_entity_endpoint(credentials_schema)(self, ...)
      end,
      DELETE = endpoints.delete_entity_endpoint(credentials_schema),
    },
  },
  ["/basic-auths/"] = {
    schema = credentials_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(credentials_schema),
    }
  },
  ["/basic-auths/:basicauth_credentials/consumer"] = {
    schema = consumers_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(
              credentials_schema, consumers_schema, "consumer"),
    }
  },
}
