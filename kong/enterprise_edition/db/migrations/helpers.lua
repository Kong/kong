local utils        = require "kong.tools.utils"

local fmt = string.format


local _M = {}


function _M.add_to_default_ws(res, id, type, field_name, field_value, def_ws_id)
    if field_value then
      table.insert(res,
        fmt("INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(%s, 'default', '%s', '%s', '%s', '%s')",
          def_ws_id, id, type, field_name, field_value))
    else
      table.insert(res,
        fmt("INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(%s, 'default', '%s', '%s', '%s', null)",
          def_ws_id, id, type, field_name))
    end
end


function _M.add_to_ws(res, ws_id, ws_name, entity_id, entity_type, unique_field_name, unique_field_value)
  return
    table.insert(res,
      fmt("INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value)"..
        "VALUES(%s, '%s', '%s', '%s', '%s', '%s')",
          ws_id,
          ws_name,
          entity_id,
          entity_type,
          unique_field_name,
          unique_field_value))
end


_M.uuid = utils.uuid

return _M
