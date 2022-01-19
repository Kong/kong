-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local websocket = {}

local new_tab = require "table.new"

---@class kong.websocket.state : table
---
---@field type        resty.websocket.protocol.type
---@field role        '"client"'|'"upstream"'
---@field data        string|nil
---@field status      integer|nil
---@field peer_status integer|nil
---@field peer_data   string|nil
---@field drop        boolean
---@field closing     boolean
---@field thread      ngx.thread

local nrec = 7

---@param ctx table
function websocket.init_state(ctx)
  ctx.KONG_WEBSOCKET_CLIENT = new_tab(0, nrec)
  ctx.KONG_WEBSOCKET_UPSTREAM = new_tab(0, nrec)
end

---@param ctx table
---@param role '"upstream"'|'"client"'
---@return kong.websocket.state
function websocket.get_state(ctx, role)
  local key = (role == "client" and "KONG_WEBSOCKET_CLIENT")
              or "KONG_WEBSOCKET_UPSTREAM"
  local state = ctx[key]
  if not state then
    error("ctx." .. key .. " does not exist")
  end

  return state
end

return websocket
