-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Consumers = {}


function Consumers:page_by_type(_, size, offset, options)
  options = options or {}
  options.type = options.type or 0

  size = size or options.size or 100

  local count = 1
  local MAX_ITERATIONS = 5
  local r, err, err_t, next_offset = self:page(size, offset, options)
  if err_t then
    return nil, err, err_t
  end

  local rows = {}
  for _, c in ipairs(r) do
    if c.type == options.type then
      table.insert(rows, c)
    end
  end

  while count < MAX_ITERATIONS and #rows < size and next_offset do
    r, err, err_t, next_offset = self:page(size - #rows, next_offset, options)
    if err_t then
      return nil, err, err_t
    end
    for _, c in ipairs(r) do
      if c.type == options.type then
        table.insert(rows, c)
      end
    end
    count = count + 1
  end

  return rows, nil, nil, next_offset
end


return Consumers
