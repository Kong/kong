-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local invalidate_consumer_cache = function(self, entity, options)
  -- skip next lines in some tests where kong.cache is not available
  if not kong.cache then
    return
  end

  local fields = { "custom_id", "username", "username_lower" }
  for _, field in ipairs(fields) do
    if entity[field] then
      local cache_key = self:cache_key(field, entity[field])
      if options and options.no_broadcast_crud_event then
        kong.cache:invalidate_local(cache_key)
      else
        kong.cache:invalidate(cache_key)
      end
    end
  end
end


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

function Consumers:delete(primary_key, options)
  local consumer = self:select(primary_key)
  if consumer then
    invalidate_consumer_cache(self, consumer, options)
  end

  return self.super.delete(self, primary_key, options)
end

function Consumers:insert(entity, options)
  if type(entity.username) == 'string' then
    entity.username_lower = entity.username:lower()
  end

  return self.super.insert(self, entity, options)
end

function Consumers:update(primary_key, entity, options)
  if type(entity.username) == 'string' then
    entity.username_lower = entity.username:lower()
  end

  local old_consumer = self:select(primary_key)
  if old_consumer then
    invalidate_consumer_cache(self, old_consumer, options)
  end

  return self.super.update(self, primary_key, entity, options)
end

function Consumers:upsert(primary_key, entity, options)
  if type(entity.username) == 'string' then
    entity.username_lower = entity.username:lower()
  end

  local old_consumer = self:select(primary_key)
  if old_consumer then
    invalidate_consumer_cache(self, old_consumer, options)
  end

  return self.super.upsert(self, primary_key, entity, options)
end

function Consumers:select_by_username_ignore_case(username)
  local consumers, err = self.strategy:select_by_username_ignore_case(username)

  if err then
    return nil, err
  end

  -- sort consumers by created_at date so that the first entry is the oldest
  table.sort(consumers, function(a,b)
    return a.created_at < b.created_at
  end)

  return consumers, nil
end


return Consumers
