-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local key_sets = {}


function key_sets:truncate()
  return self.super.truncate(self)
end


function key_sets:select(primary_key, options)
  return self.super.select(self, primary_key, options)
end


function key_sets:page(size, offset, options)
  return self.super.page(self, size, offset, options)
end


function key_sets:each(size, options)
  return self.super.each(self, size, options)
end


function key_sets:insert(entity, options)
  return self.super.insert(self, entity, options)
end


function key_sets:update(primary_key, entity, options)
  return self.super.update(self, primary_key, entity, options)
end


function key_sets:upsert(primary_key, entity, options)
  return self.super.upsert(self, primary_key, entity, options)
end


function key_sets:delete(primary_key, options)
  return self.super.delete(self, primary_key, options)
end


function key_sets:select_by_cache_key(cache_key, options)
  return self.super.select_by_cache_key(self, cache_key, options)
end


function key_sets:select_by_name(unique_value, options)
  return self.super.select_by_name(self, unique_value, options)
end


function key_sets:update_by_name(unique_value, entity, options)
  return self.super.update_by_name(self, unique_value, entity, options)
end


function key_sets:upsert_by_name(unique_value, entity, options)
  return self.super.upsert_by_name(self, unique_value, entity, options)
end


function key_sets:delete_by_name(unique_value, options)
  return self.super.delete_by_name(self, unique_value, options)
end


return key_sets
