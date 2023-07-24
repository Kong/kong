-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local filter_chains = {}

local insert = table.insert
local fmt = string.format

local EMPTY = {}


local function check_enabled_filters(self, chain)
  if not self.filters then
    local err_t = self.errors:schema_violation({
      filters = "no wasm filters are configured",
    })
    return nil, tostring(err_t), err_t
  end

  if type(chain.filters) ~= "table" then
    return true
  end

  local errs

  for i, filter in ipairs(chain.filters) do
    local name = filter.name

    -- let the standard schema validation catch invalid name errors
    if type(name) == "string"
       and not self.filters_by_name[name]
    then
      errs = errs or {}
      errs[i] = { name = "no such filter: " .. filter.name }
    end
  end

  if errs then
    local err_t = self.errors:schema_violation({
      filters = errs,
    })
    return nil, tostring(err_t), err_t
  end

  return true
end


function filter_chains:load_filters(wasm_filters)
  local filters = {}
  local filters_by_name = {}

  local errors = {}

  for i, filter in ipairs(wasm_filters or EMPTY) do
    insert(filters, filter)

    if type(filter.name) ~= "string" then
      insert(errors, fmt("filter #%d name is not a string", i))

    elseif filters_by_name[filter.name] then
      insert(errors, fmt("duplicate filter name (%s) at #%d", filter.name, i))

    else
      filters_by_name[filter.name] = filter

    end
  end

  if #errors > 0 then
    return nil, "failed to load filters: " .. table.concat(errors, ", ")
  end

  self.filters = filters
  self.filters_by_name = filters_by_name

  return true
end


function filter_chains:insert(entity, options)
  local ok, err, err_t = check_enabled_filters(self, entity)
  if not ok then
    return nil, err, err_t
  end

  return self.super.insert(self, entity, options)
end


function filter_chains:update(primary_key, entity, options)
  local ok, err, err_t = check_enabled_filters(self, entity)
  if not ok then
    return nil, err, err_t
  end

  return self.super.update(self, primary_key, entity, options)
end


function filter_chains:upsert(primary_key, entity, options)
  local ok, err, err_t = check_enabled_filters(self, entity)
  if not ok then
    return nil, err, err_t
  end

  return self.super.upsert(self, primary_key, entity, options)
end


return filter_chains
