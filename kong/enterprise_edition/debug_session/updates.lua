-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.enterprise_edition.debug_session.utils"

local log = utils.log
local ngx_ERR = ngx.ERR

local function get(last_event_id)
  ---------------------------------------------
  -- Read session info/state from control plane

  -- get sessions with updates
  -- structure like:
  -- {
  --   event_id: string,
  --   sessions: {
  --     id: string,
  --     sampling_rule: string,
  --     max_samples: number,
  --     duration: number
  --     action: enum(ACTIONS),
  --   }
  -- }
  local cp_res, err = kong.rpc:call("control_plane", "kong.debug_session.v1.get_updates", last_event_id)
  if err or cp_res == nil or type(cp_res) ~= "table" then
    return nil, "invalid response: " .. tostring(cp_res) .. " err: " .. tostring(err)
  end

  return cp_res
end

local function report_state(session_id, state)
  state = state or "done"
  local res, err = kong.rpc:call("control_plane", string.format("kong.debug_session.v1.set_%s", state), session_id)
  if not res then
    log(ngx_ERR, "failed to report completed session: ", err)
    return
  end
end

return {
  get = get,
  report_state = report_state,
}
