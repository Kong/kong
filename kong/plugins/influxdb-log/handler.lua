local HttpLogHandler = require "kong.plugins.http-log.handler"
local cjson = require "cjson"

local InfluxdbLogHandler = HttpLogHandler:extend()

InfluxdbLogHandler.PRIORITY = 1

-- influxdb util function
-- ref:https://docs.influxdata.com/influxdb/v0.13/write_protocols/write_syntax/
local function influxdb_serializer(ngx)
  return {
    tag = {
      uri = ngx.var.request_uri,
      request_uri = ngx.var.scheme.."://"..ngx.var.host..":"..ngx.var.server_port..ngx.var.request_uri,
      request_querystring = ngx.req.get_uri_args(), -- parameters, as a table
      request_method = ngx.req.get_method(), -- http method
      request_headers = ngx.req.get_headers(),
      response_status = ngx.status,
      response_headers = ngx.resp.get_headers(),
      client_ip = ngx.var.remote_addr,
      api = ngx.ctx.api,
      authenticated_entity_id = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.id,
      authenticated_entity_consumer_id = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.consumer_id
    },
    field = {
      request_size = ngx.var.request_length,
      response_size = ngx.var.bytes_sent,
      latencies_kong = (ngx.ctx.KONG_ACCESS_TIME or 0) +
               (ngx.ctx.KONG_RECEIVE_TIME or 0),
      latencies_proxy = ngx.ctx.KONG_WAITING_TIME or -1,
      latencies_request = ngx.var.request_time * 1000,
      started_at = ngx.req.start_time() * 1000
    }
  }
end

local function influxdb_escape(str)
    if type(str) ~= "string" then
        return str
    end

    return string.gsub(str, "[=, ]", function (w) return "\\"..w end)

end

-- Generates influxdb line
-- @param `measurement`, similar to MySQL table name
-- @param `message`  Message to be logged
-- @return `line` of influxdb line protocol
local function generate_influxdb_line(measurement, message)
    local line = measurement
    local flag = true

    if message.tag then
        -- Tags should be sorted by key before being sent for best performance
        -- ref: https://docs.influxdata.com/influxdb/v0.13/write_protocols/line/
        local key_table = {}
        for k, _ in pairs(message.tag) do
            table.insert(key_table, k)
        end
        table.sort(key_table)
        for _, k in ipairs(key_table) do
            local v = message.tag[k]
            line = line..","
            if type(v) == "table" then
                v = cjson.encode(v)
            end
            line = line..k.."="..influxdb_escape(v)
        end
    end

    if message.field then
        for k, v in pairs(message.field) do
            if flag then
                line = line.." "
                flag = false
            else
                line = line..","
            end
            line = line..k.."="..v
        end
    end

    return line
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
  return generate_influxdb_line("kong", influxdb_serializer(ngx))
end

return InfluxdbLogHandler
