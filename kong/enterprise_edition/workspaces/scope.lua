-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local scope = {}


-- THIS FUNCTION IS DEPRECATED!
-- Use regular DAO calls and use the options argument to specify
-- whether you want workspace information.
--
-- Examples:
--
-- * To get all elements from all workspaces:
--
--    local GLOBAL_QUERY_OPTS = { workspace = null, show_ws_id = true }
--    for row, err in db.services:each(nil, GLOBAL_QUERY_OPTS) do
--      if err then
--         return nil
--      end
--      print("Element ", row.id, " from workspace ", row.ws_id)
--    end
--
-- * To get an entry from a specific workspace:
--
--    local ws = db.workspaces:select_by_name("bla")
--    local r = db.routes:select_by_name("my-route", { workspace = ws.id })
--
function scope.run_with_ws_scope(ws, cb, ...)
  assert(type(ws) == "table" and ws.id, "ws must be a workspace table")

  local old_ws = ngx.ctx.workspace
  ngx.ctx.workspace = ws.id
  local res, err = cb(...)
  ngx.ctx.workspace = old_ws
  return res, err
end


return scope
