-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ConsumerGroupConsumers = {}


function ConsumerGroupConsumers:count_consumers_in_group(group_id)
  local PAGE_SIZE = 100
  local next_offset = nil
  local rows, err
  local len = 0
  
  repeat
    rows, err, next_offset = self:page(PAGE_SIZE, next_offset)
    if err then
      return {{ count = 0 }}
    end
    for _, row in ipairs(rows) do
      if row.consumer_group.id == group_id then
        len = len + 1
      end
    end

  until next_offset == nil

  return {{ count = len }}
end

return ConsumerGroupConsumers
