local utils  = require "kong.tools.utils"
local feature_flags, FLAGS, VALUES


local ok, feature_flags = utils.load_module_if_exists("kong.enterprise_edition.feature_flags")
if ok then
  FLAGS = feature_flags.FLAGS
  VALUES = feature_flags.VALUES
end


local req_read_body = ngx.req.read_body
local req_get_body_data = ngx.req.get_body_data
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR


local rt_body_size_limit = -1


local function init_worker()
  if not feature_flags or not feature_flags.is_enabled(FLAGS.REQUEST_TRANSFORMER_ADVANCED_ENABLE_LIMIT_BODY) then
    return true
  end

  local limit = tonumber(feature_flags.get_feature_value(VALUES.REQUEST_TRANSFORMER_ADVANCED_LIMIT_BODY_SIZE))
  if limit then
    rt_body_size_limit = limit
  end
  return true
end


local function should_transform_body()
  if not feature_flags or not feature_flags.is_enabled(FLAGS.REQUEST_TRANSFORMER_ADVANCED_ENABLE_LIMIT_BODY) then
    return true
  end

  if rt_body_size_limit == -1 then
    return true
  end

  local content_length = tonumber(ngx.var.http_content_length)
  if not content_length then
    req_read_body()
    local body = req_get_body_data()
    content_length = (body and #body) or 0
  end

  -- returns false if content_length is larger than rt_body_size_limit
  -- thus prevents transform_body from running
  if content_length > rt_body_size_limit then
    ngx_log(ngx_ERR, "[request-transformer-advanced] { \"message\": \"request body size limit exceeded\", \"allowed\" : " ..
        rt_body_size_limit .. ", \"current\" : " .. content_length .. " }")
    return false
  else
    return true
  end
end


return {
  init_worker = init_worker,
  should_transform_body = should_transform_body
}
