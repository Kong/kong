local BasePlugin = require "kong.plugins.base_plugin"
local body_filter = require "kong.plugins.response-transformer.body_transformer"
local header_filter = require "kong.plugins.response-transformer.header_transformer"

local ResponseTransformerHandler = BasePlugin:extend()

function ResponseTransformerHandler:new()
  ResponseTransformerHandler.super.new(self, "response-transformer")
end

function ResponseTransformerHandler:access(conf)
  ResponseTransformerHandler.super.access(self)
  ngx.ctx.buffer = ""
end

function ResponseTransformerHandler:header_filter(conf)
  ResponseTransformerHandler.super.header_filter(self)
  header_filter.transform_headers(conf, ngx.header)
end

function ResponseTransformerHandler:body_filter(conf)
  ResponseTransformerHandler.super.body_filter(self)
  if body_filter.is_json_body(ngx.header["content-type"]) then
    if table.getn(conf.remove.json) > 0 or table.getn(conf.replace.json) > 0 or table.getn(conf.add.json) > 0 or table.getn(conf.append.json) > 0 then 
      local chunk, eof = ngx.arg[1], ngx.arg[2]
      if eof then
        local body = body_filter.transform_json_body(conf, ngx.ctx.buffer)
        ngx.arg[1] = body
      else
        ngx.ctx.buffer = ngx.ctx.buffer..chunk
        ngx.arg[1] = nil
      end  
    end
  end  
end

ResponseTransformerHandler.PRIORITY = 800

return ResponseTransformerHandler
