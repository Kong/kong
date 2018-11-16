local feature_flags = require "kong.enterprise_edition.feature_flags"
local FLAGS = feature_flags.FLAGS
local VALUES = feature_flags.VALUES


local table_concat = table.concat
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR


local rt_body_size_limit = -1


local function init_worker()
  if not feature_flags.is_enabled(FLAGS.RESPONSE_TRANSFORMER_ENABLE_LIMIT_BODY) then
    return true
  end

  local res, _ = feature_flags.get_feature_value(VALUES.RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE)
  if not res then
    ngx_log(ngx_ERR, string.format("[response-transformer-advanced] failed to configure body size limit:" ..
                                   "\"%s\" is turned on but \"%s\" is not defined",
                                   FLAGS.RESPONSE_TRANSFORMER_ENABLE_LIMIT_BODY,
                                   VALUES.RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE))
    return false
  end

  local limit = tonumber(res)
  if not limit then
    ngx_log(ngx_ERR, string.format("[response-transformer-advanced] failed to configure body size limit:" ..
                                   "\"%s\" is not valid number for \"%s\", ",
                                   res,
                                   VALUES.RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE))
    return false
  end

  rt_body_size_limit = limit
  return true
end


local function header_filter()
  if not feature_flags.is_enabled(FLAGS.RESPONSE_TRANSFORMER_ENABLE_LIMIT_BODY) then
    return true
  end

  if rt_body_size_limit == -1 then
    return true
  end

  ngx.ctx.rt_body_size_consumed = 0

  local content_length = tonumber(ngx.header["content-length"])
  if not content_length then
    return true
  end

  -- set the flag to stop
  if content_length > rt_body_size_limit then
    ngx_log(ngx_ERR, "[response-transformer-advanced] { \"message\": \"response body size limit exceeded\", \"allowed\" : " ..
        rt_body_size_limit .. ", \"current\" : " .. content_length.. " }")
    ngx.ctx.rt_skip_body_trans = true
  end

  return true
end


local function body_filter()
  local ctx = ngx.ctx
  -- if flag is set, skip plugin's body_filter
  if ctx.rt_skip_body_trans then
    return false
  end

  -- if feature_flag is enabled but no content-length is set, we calculate the body size ourself
  if ctx.rt_body_size_consumed ~= nil then
    ctx.rt_body_size_consumed = ngx.ctx.rt_body_size_consumed + #ngx.arg[1]
    if ctx.rt_body_size_consumed > rt_body_size_limit then
      ngx_log(ngx_ERR, "[response-transformer-advanced] { \"message\": \"response body size limit exceeded\", \"allowed\" : " ..
        rt_body_size_limit .. ", \"current\" : " .. ctx.rt_body_size_consumed .. " }")
        ctx.rt_skip_body_trans = true

        -- sending out the buffered body we have so far
        ctx.rt_body_chunks[ctx.rt_body_chunk_number] = ngx.arg[1]
        ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
        ngx.arg[1] = table_concat(ctx.rt_body_chunks)
      return false
    end
  end

  return true
end


return {
  init_worker = init_worker,
  header_filter = header_filter,
  body_filter = body_filter
}
