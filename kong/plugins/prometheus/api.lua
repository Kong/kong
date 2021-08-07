-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local prometheus = require "kong.plugins.prometheus.exporter"

local printable_metric_data = function()
  return table.concat(prometheus.metric_data(), "")
end

return {
  ["/metrics"] = {
    GET = function()
      prometheus.collect()
    end,
  },

  _stream = ngx.config.subsystem == "stream" and printable_metric_data or nil,
}
