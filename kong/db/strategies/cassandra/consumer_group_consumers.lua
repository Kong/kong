-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cassandra = require "cassandra"

local ConsumerGroupConsumers = {}
local CQL = [[
    SELECT COUNT(consumer_id) as count FROM consumer_group_consumers WHERE consumer_group_id = ?
  ]]

function ConsumerGroupConsumers:count_consumers_in_group(group_id)
  local args = { cassandra.uuid(group_id) }
  
  return self.connector:query(CQL, args, nil, "read")
end

return ConsumerGroupConsumers
