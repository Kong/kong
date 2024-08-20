-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format

local Admins = {}


function Admins:select_by_username_ignore_case(username)
  local qs = fmt(
    "SELECT * FROM admins WHERE LOWER(username) = LOWER(%s);",
    kong.db.connector:escape_literal(username))

  return kong.db.connector:query(qs, "read")
end

return Admins
