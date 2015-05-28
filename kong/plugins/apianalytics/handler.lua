local http = require "resty_http"
local BasePlugin = require "kong.plugins.base_plugin"
local ALFSerializer = require "kong.plugins.log_serializers.alf"

local APIANALYTICS_SOCKET = {
  host = "localhost", -- socket.apianalytics.mashape.com
  port = 58000,
  path = "/alf_1.0.0"
}

local function send_batch(premature, conf, alf)
  local message = alf:to_json_string(conf.service_token)

  local client = http:new()
  client:set_timeout(50000) -- 5 sec

  local ok, err = client:connect(APIANALYTICS_SOCKET.host, APIANALYTICS_SOCKET.port)
  if not ok then
    ngx.log(ngx.ERR, "[apianalytics] failed to connect to the socket: "..err)
    return
  end

  local res, err = client:request({ path = APIANALYTICS_SOCKET.path, body = message })
  if not res then
    ngx.log(ngx.ERR, "[apianalytics] failed to send batch: "..err)
  end

  -- close connection, or put it into the connection pool
  if res.headers["connection"] == "close" then
    local ok, err = client:close()
    if not ok then
      ngx.log(ngx.ERR, "[apianalytics] failed to close: "..err)
    end
  else
    client:set_keepalive()
  end

  if res.status == 200 then
    alf:flush_entries()
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

  -- Retrieve and keep in memory the bodies for this request
  ngx.ctx.apianalytics = {
    req_body = "",
    res_body = ""
  }

  if conf.log_body then
    ngx.req.read_body()
    ngx.ctx.apianalytics.req_body = ngx.req.get_body_data()
  end
end

function APIAnalyticsHandler:body_filter(conf)
  APIAnalyticsHandler.super.body_filter(self)

  local chunk, eof = ngx.arg[1], ngx.arg[2]
  -- concatenate response chunks for ALF's `response.content.text`
  if conf.log_body then
    ngx.ctx.apianalytics.res_body = ngx.ctx.apianalytics.res_body..chunk
  end

  if eof then -- latest chunk
    ngx.ctx.apianalytics.response_received = ngx.now()
  end
end

function APIAnalyticsHandler:log(conf)
  APIAnalyticsHandler.super.log(self)

  local api_id = ngx.ctx.api.id

  -- Shared memory zone for apianalytics ALFs
  if not ngx.shared.apianalytics then
    ngx.shared.apianalytics = {}
  end

  -- Create the ALF if not existing for this API
  if not ngx.shared.apianalytics[api_id] then
    ngx.shared.apianalytics[api_id] = ALFSerializer:new_alf()
  end

  -- Simply adding the entry to the ALF
  local n_entries = ngx.shared.apianalytics[api_id]:add_entry(ngx)

  -- Batch size reached, let's send the data
  if n_entries >= conf.batch_size then
    local ok, err = ngx.timer.at(0, send_batch, conf, ngx.shared.apianalytics[api_id])
    if not ok then
      ngx.log(ngx.ERR, "[apianalytics] failed to create timer: ", err)
    end
  end
end

return APIAnalyticsHandler
