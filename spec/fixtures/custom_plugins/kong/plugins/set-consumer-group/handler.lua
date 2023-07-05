-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local SetConsumerGroup = {
  VERSION = "9.9.9",
  PRIORITY = 1000,
}


function SetConsumerGroup:access(conf)
  local group_name = conf.group_name
  local group_id = conf.group_id
  kong.client.set_authenticated_consumer_group({ name = group_name, id = group_id })
  ngx.header["SetConsumerGroup-Was-Executed"] = "true"
end

return SetConsumerGroup
