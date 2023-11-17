-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format

local ConsumerGroupConsumers = {}


function ConsumerGroupConsumers:count_consumers_in_group(group_id)
  local qs = fmt(
    "SELECT COUNT(consumer_id) count FROM consumer_group_consumers WHERE consumer_group_id = %s;",
    kong.db.connector:escape_literal(group_id))

  return kong.db.connector:query(qs)
end

return ConsumerGroupConsumers
