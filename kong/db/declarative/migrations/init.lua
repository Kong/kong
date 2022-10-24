-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local route_path = require "kong.db.declarative.migrations.route_path"

return function(tbl)
  if not tbl then
    -- we can not migrate without version specified
    return
  end

  route_path(tbl, tbl._format_version)

  tbl._format_version = "3.0"
end
