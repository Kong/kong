local BasePlugin = require "kong.plugins.base_plugin"
local prometheus = require "kong.plugins.prometheus.exporter"
local basic_serializer = require "kong.plugins.log-serializers.basic"


local PrometheusHandler = BasePlugin:extend()
PrometheusHandler.PRIORITY = 13
PrometheusHandler.VERSION = "0.3.4"


local function log(premature, message)
  if premature then
    return
  end

  prometheus.log(message)
end


function PrometheusHandler:new()
  PrometheusHandler.super.new(self, "prometheus")
  return prometheus.init()
end


function PrometheusHandler:log(conf) -- luacheck: ignore 212
  PrometheusHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  local ok, err = ngx.timer.at(0, log, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return PrometheusHandler
