local body_transformer = require "kong.plugins.response-transformer.body_transformer"
local header_transformer = require "kong.plugins.response-transformer.header_transformer"
local kong_meta = require "kong.meta"


local is_body_transform_set = header_transformer.is_body_transform_set
local is_json_body = header_transformer.is_json_body
local kong = kong


local ResponseTransformerHandler = {
  PRIORITY = 800,
  VERSION = kong_meta.version,
}


function ResponseTransformerHandler:header_filter(conf)
  header_transformer.transform_headers(conf, kong.response.get_headers())
end


function ResponseTransformerHandler:body_filter(conf)
  if not is_body_transform_set(conf)
    or not is_json_body(kong.response.get_header("Content-Type"))
  then
    return
  end

  local body = kong.response.get_raw_body()
  if body then
    return kong.response.set_raw_body(body_transformer.transform_json_body(conf, body))
  end
end


return ResponseTransformerHandler
