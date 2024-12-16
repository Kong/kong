-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local type = type
local fmt = string.format
local tostring = tostring


local function is_used_by_plugins(self, name)
  if type(name) ~=  "string" then
    return
  end

  local connector = self.db.connector

  name = connector:escape_literal(name)

  local sql = fmt('SELECT "id" FROM "plugins" WHERE name = %s LIMIT 1', name)
  local res, err = connector:query(sql, "read")
  if not res then
    return nil, err
  end

  return res[1] ~= nil and res[1].id or nil
end


local function is_used_error(self, name, plugin_id)
  local msg = fmt("custom plugin %q is still referenced by plugins (id = %q)", name, plugin_id)
  return self.errors:referenced_by_others(msg)
end


local function is_used(self, name)
  if name then
    local plugin_id = is_used_by_plugins(self, name)
    if plugin_id then
      return is_used_error(self, name, plugin_id)
    end
  end
end


local function by_id(func, self, pk, ...)
  local entity = self.super.select(self, pk)
  local err_t = is_used(self, entity and entity.name)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  return func(self, pk, ...)
end


local function by_name(func, self, name, ...)
  local err_t = is_used(self, name)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  return func(self, name, ...)
end


local custom_plugins = {}


function custom_plugins:delete(...)
  return by_id(self.super.delete, self, ...)
end


function custom_plugins:update(...)
  return by_id(self.super.update, self, ...)
end


function custom_plugins:upsert(...)
  return by_id(self.super.upsert, self, ...)
end


function custom_plugins:delete_by_name(...)
  return by_name(self.super.delete_by_name, self, ...)
end


function custom_plugins:update_by_name(...)
  return by_name(self.super.update_by_name, self, ...)
end


function custom_plugins:upsert_by_name(...)
  return by_name(self.super.upsert_by_name, self, ...)
end


return custom_plugins
