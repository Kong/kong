-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local workspaces   = require "kong.workspaces"
local cassandra    = require "cassandra"
local split        = require "kong.tools.utils".split

local fmt = string.format

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

  return self.super.update(self, primary_key, entity, options)
end

function Consumers:upsert(primary_key, entity, options)
  if type(entity.username) == 'string' then
    entity.username_lower = entity.username:lower()
  end

  return self.super.upsert(self, primary_key, entity, options)
end

function Consumers:select_by_username_ignore_case(username)
  local function postgres_query()
    local ws_id = workspaces.get_workspace_id()
    local qs = fmt(
      "SELECT * FROM consumers WHERE LOWER(username) = LOWER(%s) AND ws_id = %s;",
      kong.db.connector:escape_literal(username),
      kong.db.connector:escape_literal(ws_id))

    return kong.db.connector:query(qs)
  end

  local function cassandra_query()
    local ws_id = workspaces.get_workspace_id()
    local escaped_value = cassandra.text(fmt("%s:%s", ws_id, username:lower())).val
    local qs = fmt(
      "SELECT * FROM consumers WHERE username_lower = '%s';",
      escaped_value)

    local consumers, err = kong.db.connector:query(qs)

    for i,v in pairs(consumers) do
      if type(i) == "number" then
        consumers[i].username = split(consumers[i].username, ":")[2]
        consumers[i].username_lower = split(consumers[i].username_lower, ":")[2]
      end
    end

    return consumers, err
  end

  local consumers, err
  if kong.db.strategy == "postgres" then
    consumers, err = postgres_query()
  elseif kong.db.strategy == "cassandra" then
    consumers, err = cassandra_query()
  else
    -- other strategies not supported
    return nil, nil
  end

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
