local BasePlugin = require "kong.plugins.base_plugin"
local body_filter = require "kong.plugins.response-transformer-advanced.body_transformer"
local header_filter = require "kong.plugins.response-transformer-advanced.header_transformer"
local feature_flag_limit_body = require "kong.plugins.response-transformer-advanced.feature_flags.limit_body"

local is_body_transform_set = header_filter.is_body_transform_set
local is_json_body = header_filter.is_json_body
local table_concat = table.concat

local ResponseTransformerHandler = BasePlugin:extend()


function ResponseTransformerHandler:new()
  ResponseTransformerHandler.super.new(self, "response-transformer-advanced")
end

function ResponseTransformerHandler:init_worker()
  ResponseTransformerHandler.super.init_worker(self, "response-transformer-advanced")

  feature_flag_limit_body.init_worker()
end

function ResponseTransformerHandler:access(conf)
  ResponseTransformerHandler.super.access(self)

  local ctx = ngx.ctx

  ctx.rt_body_chunks = {}
  ctx.rt_body_chunk_number = 1
end

function ResponseTransformerHandler:header_filter(conf)
  ResponseTransformerHandler.super.header_filter(self)

  if not feature_flag_limit_body.header_filter() then
    return
  end

  header_filter.transform_headers(conf, ngx.header, ngx.status)
end

function ResponseTransformerHandler:body_filter(conf)
  ResponseTransformerHandler.super.body_filter(self)

  if not feature_flag_limit_body.body_filter() then
    return
  end

  if is_body_transform_set(conf) then
    local ctx = ngx.ctx

    -- Initializes context here in case this plugin's access phase
    -- did not run - and hence `rt_body_chunks` and `rt_body_chunk_number`
    -- were not initialized
    ctx.rt_body_chunks = ctx.rt_body_chunks or {}
    ctx.rt_body_chunk_number = ctx.rt_body_chunk_number or 1

    local chunk, eof = ngx.arg[1], ngx.arg[2]

    -- if eof wasn't received keep buffering
    if not eof then
      ctx.rt_body_chunks[ctx.rt_body_chunk_number] = chunk
      ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
      ngx.arg[1] = nil
      return
    end

    -- last piece of body is ready; do the thing
    local resp_body = table_concat(ctx.rt_body_chunks)

    -- raw body transformation takes precedence over
    -- json transforms
    local body = body_filter.replace_body(conf, resp_body, ngx.status)
    if body then
      ngx.arg[1] = body
      resp_body = body
    end

    -- transform json
    if is_json_body(ngx.header["content-type"]) then
      body = body_filter.transform_json_body(conf, resp_body, ngx.status)
      ngx.arg[1] = body
    end
  end
end

ResponseTransformerHandler.PRIORITY = 800
ResponseTransformerHandler.VERSION = "0.1.0"

return ResponseTransformerHandler
