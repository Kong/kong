local exporter = require "kong.plugins.prometheus.exporter"
local tbl_insert = table.insert
local tbl_concat = table.concat


local printable_metric_data = function(_)
  local buffer = {}
  -- override write_fn, since stream_api expect response to returned
  -- instead of ngx.print'ed
  exporter.metric_data(function(new_metric_data)
    tbl_insert(buffer, tbl_concat(new_metric_data, ""))
  end)

  return tbl_concat(buffer, "")
end


return {
  ["/metrics"] = {
    GET = function()
      exporter.collect()
    end,
  },

  _stream = ngx.config.subsystem == "stream" and printable_metric_data or nil,
}
