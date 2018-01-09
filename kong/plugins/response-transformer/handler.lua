local BasePlugin = require "kong.plugins.base_plugin"
local body_filter = require "kong.plugins.response-transformer.body_transformer"
local header_filter = require "kong.plugins.response-transformer.header_transformer"

local is_body_transform_set = header_filter.is_body_transform_set
local is_json_body = header_filter.is_json_body
local table_concat = table.concat

local ResponseTransformerHandler = BasePlugin:extend()


function ResponseTransformerHandler:new()
  ResponseTransformerHandler.super.new(self, "response-transformer")
end

function ResponseTransformerHandler:access(conf)
  ResponseTransformerHandler.super.access(self)

  local ctx = ngx.ctx

  ctx.rt_body_chunks = {}
  ctx.rt_body_chunk_number = 1
end

function ResponseTransformerHandler:header_filter(conf)
  ResponseTransformerHandler.super.header_filter(self)
  header_filter.transform_headers(conf, ngx.header)
end

function ResponseTransformerHandler:body_filter(conf)
  ResponseTransformerHandler.super.body_filter(self)

  if is_body_transform_set(conf) and is_json_body(ngx.header["content-type"]) then
    local ctx = ngx.ctx
    local chunk, eof = ngx.arg[1], ngx.arg[2]
    if eof then
      local body = body_filter.transform_json_body(conf, table_concat(ctx.rt_body_chunks))
      ngx.arg[1] = body
    else
      ctx.rt_body_chunks[ctx.rt_body_chunk_number] = chunk
      ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
      ngx.arg[1] = nil
    end
  end
end

ResponseTransformerHandler.PRIORITY = 800
ResponseTransformerHandler.VERSION = "0.1.0"

return ResponseTransformerHandler
