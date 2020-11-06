-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local SKey_Meta = {}


function SKey_Meta:select_existing_active()
  local rows, err = self.strategy:select_existing_active()
  if err then
    return nil, err
  end

  assert(#rows == 1 or #rows == 0)

  return rows[1]
end


function SKey_Meta:activate(id)
  return self.strategy:activate(id)
end


return SKey_Meta
