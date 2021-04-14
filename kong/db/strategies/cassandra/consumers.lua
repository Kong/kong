-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ipairs = ipairs

local Consumers = {}

-- 2. provar pg pull iterator
function Consumers:page_by_type(type, size, offset, options)
  local count = 1
  local MAX_ITERATIONS = 5
  local res, err_t, next_offset = self.super.page(self, size, offset, options)

  local r = {}
  for _, c in ipairs(res) do
    if c.type == type then
      table.insert(r, c)
    end
  end
  res = r

  while count < MAX_ITERATIONS and #res < size and next_offset do
    r, err_t, next_offset = self.super.page(self, size-#res, next_offset, options)
    for _, c in ipairs(r) do
      if c.type == type then
        table.insert(res, c)
      end
    end
    count = count + 1

    if #res == 0 then -- if we're not getting anything in a search, stop
      break
    end
  end

  return res, err_t, next_offset
end

return Consumers
