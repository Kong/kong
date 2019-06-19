local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require("cjson.safe").new()


local json_decode = cjson.decode
local ngx_req_read_body = ngx.req.read_body
local ngx_req_get_body_data = ngx.req.get_body_data


cjson.decode_array_with_array_mt(true)


local validator_cache = setmetatable({}, {
    __mode = "k",
    __index = function(self, plugin_config)
        -- it was not found, so here we generate it
        local generator = require("kong.plugins.request-validator." ..
          plugin_config.version).generate
        local validator_func = assert(generator(plugin_config))
        self[plugin_config] = validator_func
      return validator_func
    end
    })



local function get_req_body_json()
  ngx_req_read_body()

  local body_data = ngx_req_get_body_data()
  if not body_data or #body_data == 0 then
    return {}
  end

  -- try to decode body data as json
  local body, err = json_decode(body_data)
  if err then
    return nil, "request body is not valid JSON"
  end

  return body
end



local RequestValidator = BasePlugin:extend()
RequestValidator.PRIORITY = 200
RequestValidator.VERSION = "0.2.0"


function RequestValidator:new()
  RequestValidator.super.new(self, "request-validator")
end


function RequestValidator:access(conf)
  RequestValidator.super.access(self)

  -- try to retrieve cached request body schema entity
  -- if it isn't in cache, it will be created
  local validator = validator_cache[conf]

  local body, err = get_req_body_json()
  if not body then
    return kong.response.exit(400, err)
  end

  -- try to validate body against schema
  local ok, _ = validator(body)
  if not ok then
    return kong.response.exit(400, { message = "request body doesn't conform to schema" })
  end
end


return RequestValidator
