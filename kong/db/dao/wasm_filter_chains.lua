local wasm_filter_chains = {}

local insert = table.insert
local fmt = string.format
local type = type

local GLOBAL_ID = "_"

local EMPTY = {}

---@enum kong.db.schema.entities.wasm_filter_chain.type
local TYPES = {
  route   = "route",
  service = "service",
  global  = "global",
}

wasm_filter_chains.TYPES = TYPES
wasm_filter_chains.GLOBAL_ID = GLOBAL_ID


---@param typ     kong.db.schema.entities.wasm_filter_chain.type
---@param id      string
---@return string cache_key
local function make_cache_key(self, typ, id)
  return fmt("%s:%s:%s", self.schema.name, typ, id)
end


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


function wasm_filter_chains:load_filters(wasm_filters)
  local filters = {}
  local filters_by_name = {}

  local errors = {}

  for i, filter in ipairs(wasm_filters or EMPTY) do
    insert(filters, filter)

    if type(filter.name) ~= "string" then
      insert(errors, fmt("filter #%s name is not a string", i))

    elseif filters_by_name[filter.name] then
      insert(errors, fmt("duplicate filter name (%s) at #%s", filter.name, i))

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


function wasm_filter_chains:insert(entity, options)
  local ok, err, err_t = check_enabled_filters(self, entity)
  if not ok then
    return nil, err, err_t
  end

  return self.super.insert(self, entity, options)
end


function wasm_filter_chains:update(primary_key, entity, options)
  local ok, err, err_t = check_enabled_filters(self, entity)
  if not ok then
    return nil, err, err_t
  end

  return self.super.update(self, primary_key, entity, options)
end


function wasm_filter_chains:upsert(primary_key, entity, options)
  local ok, err, err_t = check_enabled_filters(self, entity)
  if not ok then
    return nil, err, err_t
  end

  return self.super.upsert(self, primary_key, entity, options)
end


---@param chain kong.db.schema.entities.wasm_filter_chain
---@return kong.db.schema.entities.wasm_filter_chain.type type
---@return string id
function wasm_filter_chains:get_type(chain)
  if type(chain.route) == "table" and chain.route.id then
    return TYPES.route, chain.route.id

  elseif type(chain.service) == "table" and chain.service.id then
    return TYPES.service, chain.service.id
  end

  return TYPES.global, GLOBAL_ID
end


---@param typ kong.db.schema.entities.wasm_filter_chain.type
---@param id? string|{ id: string }
---@return string
function wasm_filter_chains:cache_key_for(typ, id)
  assert(TYPES[typ], "invalid filter chain type: " .. tostring(typ))

  if type(id) == "table" then
    id = id.id
  end

  return make_cache_key(self, typ, id)
end


---@param chain kong.db.schema.entities.wasm_filter_chain
---@return string cache_key
function wasm_filter_chains:cache_key(chain)
  assert(type(chain) == "table", "filter chain is not a table")

  return self:cache_key_for(self:get_type(chain))
end


return wasm_filter_chains
