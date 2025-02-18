local declarative = require("kong.db.declarative")
local declarative_config = require("kong.db.schema.others.declarative_config")
local db_errors = require("kong.db.errors")
local ERRORS = require("kong.constants").CLUSTERING_DATA_PLANE_ERROR


local null = ngx.null
local insert = table.insert
local pk_string = declarative_config.pk_string
local validate_references_sync = declarative_config.validate_references_sync
local pretty_print_error = declarative.pretty_print_error


-- It refers to format_error() function in kong/clustering/config_helper.lua.
local function format_error(err_t)
  -- Declarative config parse errors will include all the input entities in
  -- the error table. Strip these out to keep the error payload size small.
  local errors = err_t.flattened_errors
  if type(errors) ~= "table" then
    return
  end

  for i = 1, #errors do
    local err = errors[i]
    if type(err) == "table" then
      err.entity = nil
    end
  end
end


local function validate_deltas(deltas, is_full_sync)

  local errs = {}
  local errs_entities = {}

  -- generate deltas table mapping primary key string to entity item
  local deltas_map = {}

  local db = kong.db

  for _, delta in ipairs(deltas) do
    local delta_type = delta.type
    local delta_entity = delta.entity

    if delta_entity ~= nil and delta_entity ~= null then

      -- validate workspace id
      local ws_id = delta_entity.ws_id or delta.ws_id
      if not ws_id or ws_id == null then
        if not errs[delta_type] then
          errs[delta_type] = {}
        end
        insert(errs[delta_type], { ["ws_id"] = "required field missing", })
      end

      -- table: primary key string -> entity
      local schema = db[delta_type].schema
      local pk = schema:extract_pk_values(delta_entity)
      local pks = pk_string(schema, pk)

      deltas_map[pks] = delta_entity

      -- validate entity
      local dao = kong.db[delta_type]
      if dao then
        -- CP will insert ws_id into the entity, which will be validated as an
        -- unknown field.
        -- TODO: On the CP side, remove ws_id from the entity and set it only
        -- in the delta.

        -- needs to insert default values into entity to align with the function
        -- dc:validate(input), which will call process_auto_fields on its
        -- entities of input.
        local copy = dao.schema:process_auto_fields(delta_entity, "insert")
        copy.ws_id = nil

        local ok, err_t = dao.schema:validate(copy)
        if not ok then
          if not errs[delta_type] then
            errs[delta_type] = {}
          end
          insert(errs[delta_type], err_t)

          if not errs_entities[delta_type] then
            errs_entities[delta_type] = {}
          end
          insert(errs_entities[delta_type], delta_entity)
        end
      end
    end
  end

  -- validate references

  if not next(errs) then
    local ok
    ok, errs = validate_references_sync(deltas, deltas_map, is_full_sync)
    if ok then
      return true
    end
  end

  -- error handling

  local err = pretty_print_error(errs)

  local err_t = db_errors:sync_deltas_flattened(errs, errs_entities)

  err_t.name = ERRORS.DELTAS_PARSE
  err_t.source = "kong.clustering.services.sync.validate.validate_deltas"

  format_error(err_t)

  return nil, err, err_t
end


return {
  validate_deltas = validate_deltas,
  format_error = format_error,
}
