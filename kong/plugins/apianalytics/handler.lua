local http = require "socket.http"
local ltn12 = require "ltn12"
local BasePlugin = require "kong.plugins.base_plugin"
local ALFSerializer = require "kong.plugins.log_serializers.alf"

local http_client = require "kong.tools.http_client"

--local SERVER_URL = "http://socket.apianalytics.com/"
local SERVER_URL = "http://localhost:58000/alf_1.0.0"

local APIAnalyticsHandler = BasePlugin:extend()

function APIAnalyticsHandler:new()
  APIAnalyticsHandler.super.new(self, "apianalytics")
end

function APIAnalyticsHandler:access(conf)
  APIAnalyticsHandler.super.access(self)

  ngx.req.read_body()
  ngx.ctx.req_body = ngx.req.get_body_data()
  ngx.ctx.res_body = ""
end

function APIAnalyticsHandler:body_filter(conf)
  APIAnalyticsHandler.super.body_filter(self)

  -- concatenate response chunks for response.content.text
  local chunk = ngx.arg[1]
  ngx.ctx.res_body = ngx.ctx.res_body..chunk
end

function APIAnalyticsHandler:log(conf)
  APIAnalyticsHandler.super.log(self)

  ALFSerializer:add_entry(ngx)

  -- if queue is full
  local message = ALFSerializer:to_json_string("54d2b98ee0d5076065fd6f93")
  print("MESSAGE: "..message)

  -- TODO: use the cosocket API
  local response, status, headers = http_client.post(SERVER_URL, message,
    {
      ["content-length"] = string.len(message),
      ["content-type"] = "application/json"
    })

  print("STATUS: "..status)
  if status ~= 200 then
    ngx.log(ngx.ERR, "Could not send entry to "..SERVER_URL)
    print("RESPONSE IS: "..response)
  end

  -- todo: flush
end

return APIAnalyticsHandler
