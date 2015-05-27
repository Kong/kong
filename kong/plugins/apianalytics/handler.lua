local http = require "resty_http"
local BasePlugin = require "kong.plugins.base_plugin"
local ALFSerializer = require "kong.plugins.log_serializers.alf"

local APIANALYTICS_SOCKET = {
  host = "localhost",
  port = 58000,
  path = "/alf_1.0.0"
}

local function send_batch(premature, message)
  local client = http:new()
  client:set_timeout(1000) -- 1 sec

  local ok, err = client:connect(APIANALYTICS_SOCKET.host, APIANALYTICS_SOCKET.port)
  if not ok then
    ngx.log(ngx.ERR, "[apianalytics] failed to connect to the socket: "..err)
    return
  end

  local res, err = client:request({ path = APIANALYTICS_SOCKET.path, body = message })
  if not res then
    ngx.log(ngx.ERR, "[apianalytics] failed to send batch: "..err)
    return
  end

  -- close connection, or put it into the connection pool
  if res.headers["connection"] == "close" then
    local ok, err = client:close()
    if not ok then
      ngx.log(ngx.ERR, "[apianalytics] failed to close: "..err)
      return
    end
  else
    client:set_keepalive()
  end

  if res.status == 200 then
    ALFSerializer:flush_entries()
    ngx.log(ngx.DEBUG, "[apianalytics] successfully saved the batch")
  else
    ngx.log(ngx.ERR, "[apianalytics] socket refused the batch: "..res.body)
  end
end

--
--
--

local APIAnalyticsHandler = BasePlugin:extend()

function APIAnalyticsHandler:new()
  APIAnalyticsHandler.super.new(self, "apianalytics")
end

function APIAnalyticsHandler:access(conf)
  APIAnalyticsHandler.super.access(self)

  ngx.req.read_body()
  ngx.ctx.apianalytics = {
    req_body = ngx.req.get_body_data(),
    res_body = ""
  }
end

function APIAnalyticsHandler:body_filter(conf)
  APIAnalyticsHandler.super.body_filter(self)

  -- concatenate response chunks for ALF's `response.content.text`
  local chunk, eof = ngx.arg[1], ngx.arg[2]
  ngx.ctx.apianalytics.res_body = ngx.ctx.apianalytics.res_body..chunk

  if eof then -- latest chunk
    ngx.ctx.apianalytics.response_received = ngx.now()
  end
end

function APIAnalyticsHandler:log(conf)
  APIAnalyticsHandler.super.log(self)

  local entries_size = ALFSerializer:add_entry(ngx)

  if entries_size > 2 then
    local message = ALFSerializer:to_json_string("54d2b98ee0d5076065fd6f93")
    print("MESSAGE: "..message)

    local ok, err = ngx.timer.at(0, send_batch, message)
    if not ok then
      ngx.log(ngx.ERR, "[apianalytics] failed to create timer: ", err)
    end
  end
end

return APIAnalyticsHandler
