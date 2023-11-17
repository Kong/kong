-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ConsumerGroupConsumers = {}

function ConsumerGroupConsumers:count_consumers_in_group(group_id)
  local res, err = self.strategy:count_consumers_in_group(group_id)
  if err then
    kong.log.err(err)
    return 0
  end
  return res[1] and res[1]["count"] or 0
end

function ConsumerGroupConsumers:page_for_consumer_group(foreign_key, size, offset, options)
  return self.super.page_for_consumer_group(self, foreign_key, size, offset, options)
end

function ConsumerGroupConsumers:page_for_consumer(foreign_key, size, offset, options)
  return self.super.page_for_consumer(self, foreign_key, size, offset, options)
end

return ConsumerGroupConsumers
