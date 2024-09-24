-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local event_hooks    = require "kong.enterprise_edition.event_hooks"
local get_request_id = require("kong.observability.tracing.request_id").get
local kong = kong

local EventHooksHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 1000,
}


function EventHooksHandler:init_worker()
  event_hooks.publish("foo", "bar", {
    fields = { "msg" },
  })
end


function EventHooksHandler:access()
  local ok, err = event_hooks.emit("foo", "bar", {
    msg = "Trigger an event in access phase, request_id: " .. get_request_id(),
  }, true)

  if not ok then
    kong.log.warn("failed to emit event: ", err)
  end
end

function EventHooksHandler:header_filter()
  kong.response.add_header("x-event-hooks-enabled", kong.configuration.event_hooks_enabled)
end

return EventHooksHandler
