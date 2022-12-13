local exporter = require "kong.plugins.prometheus.exporter"

local printable_metric_data = function()
  local buffer = {}
  -- override write_fn, since stream_api expect response to returned
  -- instead of ngx.print'ed
  exporter.metric_data(function(data)
    table.insert(buffer, table.concat(data, ""))
  end)

  return table.concat(buffer, "")
end

return {
  ["/metrics"] = {
    GET = function()
      exporter.collect()
    end,
  },

  _stream = ngx.config.subsystem == "stream" and printable_metric_data or nil,
}
