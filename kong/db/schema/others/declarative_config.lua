local uuid = require("resty.jit-uuid")
local utils = require("kong.tools.utils")
local Errors = require("kong.db.errors")
local Entity = require("kong.db.schema.entity")
local Schema = require("kong.db.schema")
local constants = require("kong.constants")
local plugin_loader = require("kong.db.schema.plugin_loader")
local schema_topological_sort = require "kong.db.schema.topological_sort"


local null = ngx.null
local type = type
local next = next
local pairs = pairs
local ipairs = ipairs
local insert = table.insert
local concat = table.concat
local tostring = tostring
local cjson_encode = require("cjson.safe").encode
local yield = require("kong.tools.utils").yield

local DeclarativeConfig = {}


local all_schemas
local errors = Errors.new("declarative")


-- Maps a foreign fields to foreign entity names
-- e.g. `foreign_references["routes"]["service"] = "services"`
local foreign_references = {}

-- Maps an entity to entities that foreign-reference it
-- e.g. `foreign_children["services"]["routes"] = "service"`
local foreign_children = {}


function DeclarativeConfig.pk_string(schema, object)
  if #schema.primary_key == 1 then
    return tostring(object[schema.primary_key[1]])
  else
    local out = {}
    for _, k in ipairs(schema.primary_key) do
      insert(out, tostring(object[k]))
    end
    return concat(out, ":")
  end
end


--[[
-- Validation function to check that the generated schema did not leak any entries of type "foreign"
local function no_foreign(tbl, indent)
  indent = indent or 0
  local allok = true
  for k,v in pairs(tbl) do
    if k == "type" and v == "foreign" then
      return false
    end
    if type(v) == "table" then
      local ok = no_foreign(v, indent + 1)
      if not ok then
        print(("   "):rep(indent) .. "failed: " .. tostring(k))
        allok = false
      end
    end
  end
  return allok and tbl or nil
end
--]]


local function add_extra_attributes(fields, opts)
  if opts._comment then
    insert(fields, {
      _comment = { type = "string", },
    })
  end
  if opts._ignore then
    insert(fields, {
      _ignore = { type = "array", elements = { type = "any" } },
    })
  end
end


-- Add the keys for each entity type at the top-level of
-- the file format (`routes:`, `services:`, etc.)
--
-- @tparam array<table> fields The array of fields of the schema.
-- This array is modified by having elements added to it.
-- @tparam array<string> entities The list of entity names
-- @treturn map<string,table> A map of record definitions added to `fields`,
-- indexable by entity name
local function add_top_level_entities(fields, known_entities)
  local records = {}

  for _, entity in ipairs(known_entities) do
    local definition = utils.deep_copy(all_schemas[entity], false)

    for k, _ in pairs(definition.fields) do
      if type(k) ~= "number" then
        definition.fields[k] = nil
      end
    end

    definition.type = "record"
    definition.name = nil
    definition.dao = nil
    definition.primary_key = nil
    definition.endpoint_key = nil
    definition.cache_key = nil
    definition.cache_key_set = nil
    records[entity] = definition
    add_extra_attributes(records[entity].fields, {
      _comment = true,
      _ignore = true,
    })
    insert(fields, {
      [entity] = {
        type = "array",
        elements = records[entity],
      }
    })
  end

  return records
end


local function copy_record(record, include_foreign, duplicates, name)
  local copy = utils.deep_copy(record, false)
  if include_foreign then
    return copy
  end

  for i = #copy.fields, 1, -1 do
    local f = copy.fields[i]
    local _, fdata = next(f)
    if fdata.type == "foreign" then
      fdata.eq = null
      fdata.default = null
      fdata.required = false
    end
  end

  if duplicates and name then
    duplicates[name] = duplicates[name] or {}
    insert(duplicates[name], copy)
  end

  return copy
end


-- Replace keys of type `foreign` with nested records in the schema,
-- allowing for representation of relationships through nesting.
-- In a 1-n relationship (e.g. 1 service - n routes), adds the children
-- list in the parent entity (e.g. a `routes` array in `service`)
-- and replaces the parent key in the child entity with a string key.
-- (e.g. `service` as a string key in the `routes` entry).
-- @tparam map<string,table> records A map of top-level record definitions,
-- indexable by entity name. These records are modified in-place.
local function nest_foreign_relationships(known_entities, records, include_foreign)
  local duplicates = {}
  for i = #known_entities, 1, -1 do
    local entity = known_entities[i]
    local record = records[entity]
    for _, f in ipairs(record.fields) do
      local _, fdata = next(f)
      if fdata.type == "foreign" then
        local ref = fdata.reference
        -- allow nested entities
        -- (e.g. `routes` inside `services`)
        insert(records[ref].fields, {
          [entity] = {
            type = "array",
            elements = copy_record(record, include_foreign, duplicates, entity),
          },
        })

        for _, dest in ipairs(duplicates[ref] or {}) do
          insert(dest.fields, {
            [entity] = {
              type = "array",
              elements = copy_record(record, include_foreign, duplicates, entity)
            }
          })
        end
      end
    end
  end
end


local function reference_foreign_by_name(known_entities, records)
  for i = #known_entities, 1, -1 do
    local entity = known_entities[i]
    local record = records[entity]
    for _, f in ipairs(record.fields) do
      local fname, fdata = next(f)
      if fdata.type == "foreign" then
        if not foreign_references[entity] then
          foreign_references[entity] = {}
        end
        foreign_references[entity][fname] = fdata.reference
        foreign_children[fdata.reference] = foreign_children[fdata.reference] or {}
        foreign_children[fdata.reference][entity] = fname
        -- reference foreign by key in a top-level entry
        -- (e.g. `service` in a top-level `routes`)
        fdata.type = "string"
        fdata.schema = nil
        fdata.reference = nil
        fdata.on_delete = nil
      end
    end
  end
end


local function build_fields(known_entities, include_foreign)
  local fields = {
    { _format_version = { type = "string", required = true, one_of = {"1.1", "2.1"} } },
    { _transform = { type = "boolean", default = true } },
  }
  add_extra_attributes(fields, {
    _comment = true,
    _ignore = true,
  })

  local records = add_top_level_entities(fields, known_entities)
  nest_foreign_relationships(known_entities, records, include_foreign)

  return fields, records
end


local function load_plugin_subschemas(fields, plugin_set, indent)
  if not fields then
    return true
  end

  indent = indent or 0

  for _, f in ipairs(fields) do
    local fname, fdata = next(f)

    -- Exclude cases where `plugins` are used expect from plugins entities.
    -- This assumes other entities doesn't have `name` as its subschema_key.
    if fname == "plugins" and fdata.elements and fdata.elements.subschema_key == "name" then
      for plugin in pairs(plugin_set) do
        local _, err = plugin_loader.load_subschema(fdata.elements, plugin, errors)

        if err then
          return nil, err
        end
      end

    elseif fdata.type == "array" and fdata.elements.type == "record" then
      local ok, err = load_plugin_subschemas(fdata.elements.fields, plugin_set, indent + 1)
      if not ok then
        return nil, err
      end

    elseif fdata.type == "record" then
      local ok, err = load_plugin_subschemas(fdata.fields, plugin_set, indent + 1)
      if not ok then
        return nil, err
      end
    end
  end

  return true
end


local function populate_references(input, known_entities, by_id, by_key, expected, parent_entity)
  for _, entity in ipairs(known_entities) do
    if type(input[entity]) ~= "table" then
      goto continue
    end

    local foreign_refs = foreign_references[entity]

    local parent_fk
    local child_key
    if parent_entity then
      local parent_schema = all_schemas[parent_entity]
      if parent_schema.fields[entity] then
        goto continue
      end
      parent_fk = parent_schema:extract_pk_values(input)
      child_key = foreign_children[parent_entity][entity]
    end

    local entity_schema = all_schemas[entity]
    for i, item in ipairs(input[entity]) do

      populate_references(item, known_entities, by_id, by_key, expected, entity)

      local item_id = DeclarativeConfig.pk_string(entity_schema, item)
      by_id[entity] = by_id[entity] or {}
      by_id[entity][item_id] = item

      local key
      if entity_schema.endpoint_key then
        key = item[entity_schema.endpoint_key]
        if key then
          by_key[entity] = by_key[entity] or {}
          by_key[entity][key] = item
        end
      end

      if foreign_refs then
        for k, v in pairs(item) do
          local ref = foreign_refs[k]
          if ref and v ~= null then
            expected[entity] = expected[entity] or {}
            expected[entity][ref] = expected[entity][ref] or {}
            insert(expected[entity][ref], {
              key = k,
              value = v,
              at = key or item_id or i
            })
          end
        end
      end

      if parent_fk then
        item[child_key] = utils.deep_copy(parent_fk, false)
      end
    end

    ::continue::
  end
end


local function find_entity(key, entity, by_key, by_id)
  return (by_key[entity] and by_key[entity][key])
      or (by_id[entity]  and by_id[entity][key])
end


local function validate_references(self, input)
  local by_id = {}
  local by_key = {}
  local expected = {}

  populate_references(input, self.known_entities, by_id, by_key, expected)

  local errors = {}

  for a, as in pairs(expected) do
    for b, bs in pairs(as) do
      for _, k in ipairs(bs) do
        local found = find_entity(k.value, b, by_key, by_id)

        if not found then
          errors[a] = errors[a] or {}
          errors[a][k.at] = errors[a][k.at] or {}
          local msg = "invalid reference '" .. k.key .. ": " ..
                      (type(k.value) == "string"
                      and k.value or cjson_encode(k.value)) ..
                      "' (no such entry in '" .. b .. "')"
          insert(errors[a][k.at], msg)
        end
      end
    end
  end

  if next(errors) then
    return nil, errors
  end

  return by_id, by_key
end


-- This is a best-effort generation of a cache-key-like identifier
-- to feed the hash when generating deterministic UUIDs.
-- We do not use the actual `cache_key` function from the DAO because
-- at this point we don't have the auto-generated values populated
-- by process_auto_fields. Whenever we are missing a needed value to
-- ensure uniqueness, we bail out and return `nil` (instead of
-- producing an incorrect identifier that may not be unique).
local function build_cache_key(entity, item, schema, parent_fk, child_key)
  local ck = { entity }
  for _, k in ipairs(schema.cache_key) do
    if schema.fields[k].auto then
      return nil

    elseif type(item[k]) == "string" then
      insert(ck, item[k])

    elseif item[k] == nil then
      if k == child_key then
        if parent_fk.id and next(parent_fk, "id") == nil then
          insert(ck, parent_fk.id)
        else
          -- FIXME support building cache_keys with fk's whose pk is not id
          return nil
        end

      elseif schema.fields[k].required then
        return nil

      else
        insert(ck, "")
      end
    end
  end
  return concat(ck, ":")
end


local uuid_generators = {
  _entities = uuid.factory_v5("fd02801f-0957-4a15-a55a-c8d9606f30b5"),
}


local function generate_uuid(namespace, name)
  local factory = uuid_generators[namespace]
  if not factory then
    factory = uuid.factory_v5(uuid_generators["_entities"](namespace))
    uuid_generators[namespace] = factory
  end
  return factory(name)
end


local function get_key_for_uuid_gen(entity, item, schema, parent_fk, child_key)
  if #schema.primary_key ~= 1 then
    -- entity schema has a composite PK
    return
  end

  local pk_name = schema.primary_key[1]
  if item[pk_name] ~= nil then
    -- PK is already set, do not generate UUID
    return
  end

  if schema.fields[pk_name].uuid ~= true then
    -- PK is not a UUID
    return
  end

  if schema.endpoint_key and item[schema.endpoint_key] ~= nil then
    local key = item[schema.endpoint_key]

    -- check if the endpoint key is globally unique
    if not schema.fields[schema.endpoint_key].unique then
      -- If it isn't, and this item has foreign keys with on_delete "cascade",
      -- we assume that it is unique relative to the parent (e.g. targets of
      -- an upstream). We compose the item's key with the parent's key,
      -- preventing it from being overwritten by identical endpoint keys
      -- declared under other parents.
      for fname, field in schema:each_field(item) do
        if field.type == "foreign" and field.on_delete == "cascade" then
          if parent_fk then
            local foreign_key_keys = all_schemas[field.reference].primary_key
            for _, fk_pk in ipairs(foreign_key_keys) do
              key = key .. ":" .. parent_fk[fk_pk]
            end
          else
            key = key .. ":" .. item[fname]
          end
        end
      end
    end

    -- generate a PK based on the endpoint_key
    return pk_name, key
  end

  if schema.cache_key then
    return pk_name, build_cache_key(entity, item, schema, parent_fk, child_key)
  end

  return pk_name
end


local function generate_ids(input, known_entities, parent_entity)
  for _, entity in ipairs(known_entities) do
    if type(input[entity]) ~= "table" then
      goto continue
    end

    local parent_fk
    local child_key
    if parent_entity then
      local parent_schema = all_schemas[parent_entity]
      if parent_schema.fields[entity] then
        goto continue
      end
      parent_fk = parent_schema:extract_pk_values(input)
      child_key = foreign_children[parent_entity][entity]
    end

    local schema = all_schemas[entity]
    for i, item in ipairs(input[entity]) do
      local pk_name, key = get_key_for_uuid_gen(entity, item, schema,
                                                parent_fk, child_key)
      if key then
        item = utils.deep_copy(item, false)
        item[pk_name] = generate_uuid(schema.name, key)
        input[entity][i] = item
      end

      generate_ids(item, known_entities, entity)
    end

    ::continue::
  end
end


local function populate_ids_for_validation(input, known_entities, parent_entity, by_id, by_key)
  local by_id  = by_id  or {}
  local by_key = by_key or {}
  for _, entity in ipairs(known_entities) do
    if type(input[entity]) ~= "table" then
      goto continue
    end

    local parent_fk
    local child_key
    if parent_entity then
      local parent_schema = all_schemas[parent_entity]
      if parent_schema.fields[entity] then
        goto continue
      end
      parent_fk = parent_schema:extract_pk_values(input)
      child_key = foreign_children[parent_entity][entity]
    end

    local schema = all_schemas[entity]
    for _, item in ipairs(input[entity]) do
      local pk_name, key = get_key_for_uuid_gen(entity, item, schema,
                                                parent_fk, child_key)
      if pk_name and not item[pk_name] then
        if key then
          item[pk_name] = generate_uuid(schema.name, key)
        else
          item[pk_name] = utils.uuid()
        end
      end

      populate_ids_for_validation(item, known_entities, entity, by_id, by_key)

      local item_id = DeclarativeConfig.pk_string(schema, item)
      by_id[entity] = by_id[entity] or {}
      by_id[entity][item_id] = item

      local key
      if schema.endpoint_key then
        key = item[schema.endpoint_key]
        if key then
          by_key[entity] = by_key[entity] or {}
          by_key[entity][key] = item
        end
      end

      if parent_fk and not item[child_key] then
        item[child_key] = utils.deep_copy(parent_fk, false)
      end
    end

    ::continue::
  end

  if not parent_entity then
    for entity, entries in pairs(by_id) do
      local schema = all_schemas[entity]
      for _, entry in pairs(entries) do
        for name, field in schema:each_field(entry) do
          if field.type == "foreign" and type(entry[name]) == "string" then
            local found = find_entity(entry[name], field.reference, by_key, by_id)
            if found then
              entry[name] = all_schemas[field.reference]:extract_pk_values(found)
            end
          end
        end
      end
    end
  end
end


local function extract_null_errors(err)
  local ret = {}
  for k, v in pairs(err) do
    local t = type(v)
    if t == "table" then
      local res = extract_null_errors(v)
      if not next(res) then
        ret[k] = nil
      else
        ret[k] = res
      end

    elseif t == "string" and v ~= "value must be null" then
      ret[k] = nil
    else
      ret[k] = v
    end
  end

  return ret
end


local function find_default_ws(entities)
  for _, v in pairs(entities.workspaces or {}) do
    if v.name == "default" then return v.id end
  end
end


local function insert_default_workspace_if_not_given(_, entities)
  local default_workspace = find_default_ws(entities) or "0dc6f45b-8f8d-40d2-a504-473544ee190b"

  if not entities.workspaces then
    entities.workspaces = {}
  end

  if not entities.workspaces[default_workspace] then
    local entity = all_schemas["workspaces"]:process_auto_fields({
      name = "default",
      id = default_workspace,
    }, "insert")
    entities.workspaces[default_workspace] = entity
  end
end


local function flatten(self, input)
  -- manually set transform here
  -- we can't do this in the schema with a `default` because validate
  -- needs to happen before process_auto_fields, which
  -- is the one in charge of filling out default values
  if input._transform == nil then
    input._transform = true
  end

  local ok, err = self:validate(input)
  if not ok then
    yield()

    -- the error may be due entity validation that depends on foreign entity,
    -- and that is the reason why we try to validate the input again with the
    -- filled foreign keys
    if not self.full_schema then
      self.full_schema = DeclarativeConfig.load(self.plugin_set, true)
    end

    local input_copy = utils.deep_copy(input, false)
    populate_ids_for_validation(input_copy, self.known_entities)
    local ok2, err2 = self.full_schema:validate(input_copy)
    if not ok2 then
      local err3 = utils.deep_merge(err2, extract_null_errors(err))
      return nil, err3
    end

    yield()
  end

  generate_ids(input, self.known_entities)

  yield()

  local processed = self:process_auto_fields(input, "insert")

  yield()

  local by_id, by_key = validate_references(self, processed)
  if not by_id then
    return nil, by_key
  end

  yield()

  local meta = {}
  for key, value in pairs(processed) do
    if key:sub(1,1) == "_" then
      meta[key] = value
    end
  end

  local entities = {}
  for entity, entries in pairs(by_id) do
    yield(true)

    local schema = all_schemas[entity]
    entities[entity] = {}
    for id, entry in pairs(entries) do
      local flat_entry = {}
      for name, field in schema:each_field(entry) do
        if field.type == "foreign" and type(entry[name]) == "string" then
          local found = find_entity(entry[name], field.reference, by_key, by_id)
          if found then
            flat_entry[name] = all_schemas[field.reference]:extract_pk_values(found)
          end

        else
          flat_entry[name] = entry[name]
        end
      end

      entities[entity][id] = flat_entry
    end
  end

  return entities, nil, meta
end


local function load_entity_subschemas(entity_name, entity)
  local ok, subschemas = utils.load_module_if_exists("kong.db.schema.entities." .. entity_name .. "_subschemas")
  if ok then
    for name, subschema in pairs(subschemas) do
      local ok, err = entity:new_subschema(name, subschema)
      if not ok then
        return nil, ("error initializing schema for %s: %s"):format(entity_name, err)
      end
    end
  end

  return true
end


function DeclarativeConfig.load(plugin_set, include_foreign)
  all_schemas = {}
  local schemas_array = {}
  for _, entity in ipairs(constants.CORE_ENTITIES) do
    -- tags are treated differently from the rest of entities in declarative config
    if entity ~= "tags" then
      local mod = require("kong.db.schema.entities." .. entity)
      local schema = Entity.new(mod)
      all_schemas[entity] = schema
      schemas_array[#schemas_array + 1] = schema

      -- load core entities subschemas
      assert(load_entity_subschemas(entity, schema))
    end
  end

  for plugin in pairs(plugin_set) do
    local entities, err = plugin_loader.load_entities(plugin, errors,
                                           plugin_loader.load_entity_schema)
    if err then
      return nil, err
    end
    for entity, schema in pairs(entities) do
      all_schemas[entity] = schema
      schemas_array[#schemas_array + 1] = schema
    end
  end

  schemas_array = schema_topological_sort(schemas_array)

  local known_entities = {}
  for i, schema in ipairs(schemas_array) do
    known_entities[i] = schema.name
  end

  local fields, records = build_fields(known_entities, include_foreign)
  -- assert(no_foreign(fields))

  local ok, err = load_plugin_subschemas(fields, plugin_set)
  if not ok then
    return nil, err
  end

  -- we replace the "foreign"-type fields at the top-level
  -- with "string"-type fields only after the subschemas have been loaded,
  -- otherwise they will detect the mismatch.
  if not include_foreign then
    reference_foreign_by_name(known_entities, records)
  end

  local def = {
    name = "declarative_config",
    primary_key = {},
    fields = fields,
  }

  local schema = Schema.new(def)

  schema.known_entities = known_entities
  schema.flatten = flatten
  schema.insert_default_workspace_if_not_given = insert_default_workspace_if_not_given
  schema.plugin_set = plugin_set

  return schema, nil, def
end


return DeclarativeConfig
