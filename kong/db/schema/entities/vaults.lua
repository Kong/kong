local typedefs = require "kong.db.schema.typedefs"


local VAULTS do
  local i = 0
  local pairs = pairs
  local names = {}
  local constants = require "kong.constants"

  local loaded_vaults = kong and kong.configuration and kong.configuration.loaded_vaults
  if loaded_vaults then
    for name in pairs(loaded_vaults) do
      if not names[name] then
        names[name] = true
        i = i + 1
        if i == 1 then
          VAULTS = { name }
        else
          VAULTS[i] = name
        end
      end
    end

  else
    local bundled = constants and constants.BUNDLED_VAULTS
    if bundled then
      for name in pairs(bundled) do
        if not names[name] then
          names[name] = true
          i = i + 1
          if i == 1 then
            VAULTS = { name }
          else
            VAULTS[i] = name
          end
        end
      end
    end
  end
end


return {
  name = "vaults",
  table_name = "sm_vaults",
  primary_key = { "id" },
  cache_key = { "prefix" },
  endpoint_key = "prefix",
  workspaceable = true,
  subschema_key = "name",
  subschema_error = "vault '%s' is not installed",
  admin_api_name = "vaults",
  dao = "kong.db.dao.vaults",
  fields = {
    { id = typedefs.uuid },
    -- note: prefix must be valid in a host part of vault reference uri:
    -- {vault://<vault-prefix>/<secret-id>[/<secret-key]}
    { prefix = { type = "string", required = true, unique = true, unique_across_ws = true,
                 match = [[^[a-z][a-z%d-]-[a-z%d]+$]], not_one_of = VAULTS }},
    { name = { type = "string", required = true }},
    { description = { type = "string" }},
    { config = { type = "record", abstract = true }},
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    { tags = typedefs.tags },
  },
}
