local BasePlugin = require "kong.plugins.base_plugin"

local IntrospectionEndpointHandler = BasePlugin:extend()

IntrospectionEndpointHandler.PRIORITY = 1000

function IntrospectionEndpointHandler:new()
  IntrospectionEndpointHandler.super.new(self, "introspection-endpoint")
end

function IntrospectionEndpointHandler:access(conf)
  IntrospectionEndpointHandler.super.access(self)

  ngx.req.set_header("Content-Type", "application/json")

  if ngx.req.get_method() == "POST" then
    ngx.req.read_body()
    local args = ngx.req.get_post_args()
    if not args then
      return ngx.exit(500)
    end
    if args.token == "valid" or
      args.token == "valid_consumer_client_id" or
      args.token == "valid_consumer" or
      args.token == "valid_consumer_limited" or
      args.token == "valid_complex" then

      if args.token == "valid_consumer" then
        ngx.say([[{"active":true,
                   "username":"bob"}]])
      elseif args.token == "valid_consumer_client_id" then -- omit `username`, return `client_id`
        ngx.say([[{"active":true,
                    "client_id": "kongsumer"}]])
      elseif args.token == "valid_consumer_limited" then
        ngx.say([[{"active":true,
                   "username":"limited-bob"}]])
      elseif args.token == "valid_complex" then
        ngx.say([[{"active":true,
                   "username":"some_username",
                   "client_id":"some_client_id",
                   "scope":"some_scope",
                   "sub":"some_sub",
                   "aud":"some_aud",
                   "iss":"some_iss",
                   "exp":"some_exp",
                   "iat":"some_iat"}]])
      else
        ngx.say([[{"active":true}]])
      end
      return ngx.exit(200)
    end
  end

  ngx.say([[{"active":false}]])
  return ngx.exit(200)
end

return IntrospectionEndpointHandler
