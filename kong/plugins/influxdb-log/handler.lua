local HttpLogHandler = require "kong.plugins.http-log.handler"

local InfluxdbLogHandler = HttpLogHandler:extend()

InfluxdbLogHandler.PRIORITY = 1

local concat = table.concat
local sort = table.sort

-- influxdb util function
local function influxdb_point(ngx)
  local var = ngx.var
  local ctx = ngx.ctx
  local authenticated_credential = ctx.authenticated_credential
  local method = ngx.req.get_method()
  local started_at = ngx.req.start_time()
  return {
    tag = {
      scheme = var.scheme,
      host = var.host,
      uri = var.uri,
      request_method = method, -- http method
      response_status = ngx.status,
      client_ip = var.remote_addr,
      api_id = ctx.api.id,
      authenticated_entity_id = authenticated_credential and authenticated_credential.id,
      authenticated_entity_consumer_id = authenticated_credential and authenticated_credential.consumer_id
    },
    field = {
      request_size = var.request_length,
      response_size = var.bytes_sent,
      latencies_kong = (ctx.KONG_ACCESS_TIME or 0) + (ctx.KONG_RECEIVE_TIME or 0),
      latencies_proxy = ctx.KONG_WAITING_TIME or -1,
      latencies_request = var.request_time * 1000,
      started_at = started_at * 1000
    }
  }
end

-- Generates influxdb line
-- ref:https://docs.influxdata.com/influxdb/v0.13/write_protocols/write_syntax/
-- @param `measurement`, similar to MySQL table name
-- @param `message`  Message to be logged
-- @return `line` of influxdb line protocol
local function generate_influxdb_line(measurement, message)
  local tmp = {measurement, ","}
  local pointer = 3
  local tag = message.tag
  local field = message.field

  if tag then
    -- Tags should be sorted by key before being sent for best performance
    -- ref: https://docs.influxdata.com/influxdb/v1.0/write_protocols/line/
    local key_table = {}
    for k, _ in pairs(tag) do
        key_table[#key_table+1] = k
    end
    sort(key_table)

    for _, k in ipairs(key_table) do
      tmp[pointer] = k
      tmp[pointer+1] = "="
      tmp[pointer+2] = tag[k]
      tmp[pointer+3] = ","
      pointer = pointer + 4
    end
  end
  --Delete trailing comma
  tmp[#tmp] = ""

  if field then
    if tag then
      tmp[pointer] = " "
      pointer = pointer + 1
    end

    for k, v in pairs(field) do
      tmp[pointer] = k
      tmp[pointer+1] = "="
      tmp[pointer+2] = v
      tmp[pointer+3] = ","
      pointer = pointer + 4
    end
  end
  --Delete trailing comma
  tmp[#tmp] = ""

  return concat(tmp)
end

-- influx util function end

-- Only provide `name` when deriving from this class. Not when initializing an instance.
function InfluxdbLogHandler:new(name)
  InfluxdbLogHandler.super.new(self, name or "influxdb-log")
end

-- serializes context data into an influxdb-line-protocol body
-- @param `ngx` The context table for the request being logged
-- @return html body as string
function InfluxdbLogHandler:serialize(ngx)
  return generate_influxdb_line("kong", influxdb_point(ngx))
end

return InfluxdbLogHandler
