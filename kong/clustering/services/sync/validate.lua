local declarative = require("kong.db.declarative")
local declarative_config = require("kong.db.schema.others.declarative_config")


local null = ngx.null
local pk_string = declarative_config.pk_string
local validate_references_sync = declarative_config.validate_references_sync
local pretty_print_error = declarative.pretty_print_error


local function validate_deltas(deltas, is_full_sync)

  local errs = {}

  -- generate deltas table mapping primary key string to entity item
  local deltas_map = {}

  local db = kong.db

  for _, delta in ipairs(deltas) do
    local delta_type = delta.type
    local delta_entity = delta.entity

    if delta_entity ~= nil and delta_entity ~= null then
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
          errs[#errs + 1] = { [delta_type] = err_t }
        end
      end
    end
  end

  if next(errs) then
    return nil, pretty_print_error(errs, "deltas")
  end

  -- validate references
  local ok, err_t = validate_references_sync(deltas, deltas_map, is_full_sync)
  if not ok then
    return nil, pretty_print_error(err_t)
  end

  return true
end


return {
  validate_deltas = validate_deltas,
}
