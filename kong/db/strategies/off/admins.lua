-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Admins = {}


function Admins:select_by_username_ignore_case(username)
  local PAGE_SIZE = 100
  local next_offset = nil
  local rows, err
  local matches = {}

  repeat
    rows, err, next_offset = self:page(PAGE_SIZE, next_offset)
    if err then
      return nil, err
    end
    for _, row in ipairs(rows) do
      if type(row.username) == 'string' and row.username:lower() == username:lower() then
        table.insert(matches, row)
      end
    end

  until next_offset == nil

  return matches, nil
end

return Admins
