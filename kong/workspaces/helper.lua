local singletons = require "kong.singletons"
local workspaces = require "kong.workspaces"
local utils      = require "kong.tools.utils"


local pairs        = pairs
local ipairs       = ipairs
local fmt          = string.format
local tostring     = tostring
local table_concat = table.concat
local ngx_null     = ngx.null
local utils_split  = utils.split


local workspaceable = workspaces.get_workspaceable_relations()
local workspace_delimiter = workspaces.WORKSPACE_DELIMITER
local get_workspaces = workspaces.get_workspaces
local find_entity_by_unique_field = workspaces.find_entity_by_unique_field
local DEFAULT_WORKSPACE = workspaces.DEFAULT_WORKSPACE


local _M = {}


-- used only with insert, update and delete
function _M.apply_unique_per_ws(table_name, params, constraints)
  -- entity may have workspace_id, workspace_name fields, ex. in case of update
  -- needs to be removed as entity schema doesn't support them
  if table_name ~= "workspace_entities" then
    params.workspace_id = nil
  end
  params.workspace_name = nil

  if not constraints then
    return
  end

  local workspace = get_workspaces()[1]
  if not workspace or table_name == "workspaces" then
    return workspace
  end

  for field_name, field_schema in pairs(constraints.unique_keys) do
    -- skip if no unique key or it's also a primary, field
    -- is not set or has null value
    if params[field_name] and constraints.primary_key ~= field_name and
      field_schema.type ~= "id" and  params[field_name] ~= ngx_null then
      params[field_name] = fmt("%s%s%s", workspace.name, workspace_delimiter,
                               params[field_name])
    end
  end

  return workspace
end


-- If entity has a unique key it will have workspace_name prefix so we
-- have to search first in the relationship table
function _M.resolve_shared_entity_id(table_name, params, constraints)
  if not constraints or not constraints.unique_keys then
    return
  end

  local ws_scope = get_workspaces()
  if #ws_scope == 0 then
    return
  end
  local workspace = ws_scope[1]

  if table_name == "workspaces" and
    params.name == DEFAULT_WORKSPACE then
    return
  end

  for k, v in pairs(params) do
    if constraints.unique_keys[k] then
      local row, err = find_entity_by_unique_field({
        workspace_id = workspace.id,
        entity_type = table_name,
        unique_field_name = k,
        unique_field_value = v,
      })

      if err then
        return nil, err
      end

      if row then
        return { [constraints.primary_key] = row.entity_id }
      end
    end
  end
end


-- validates that given primary_key belongs to current ws scope
function _M.validate_pk_exist(table_name, params, constraints)
  if not constraints or not constraints.primary_key then
    return
  end

  local ws_scope = get_workspaces()
  if #ws_scope == 0 then
    return true
  end
  local workspace = ws_scope[1]

  if table_name == "workspaces" and
    params.name == DEFAULT_WORKSPACE then
    return true
  end

  local row, err = find_entity_by_unique_field({
    workspace_id = workspace.id,
    entity_id = params[constraints.primary_key]
  })

  if err then
    return false, err
  end

  return row and true
end


function _M.remove_ws_prefix(table_name, row, include_ws)
  if not row then
    return row
  end

  local constraints = workspaceable[table_name]
  if not constraints or not constraints.unique_keys then
    return row
  end

  for field_name, field_schema in pairs(constraints.unique_keys) do
    -- skip if no unique key or it's also a primary, field
    -- is not set or has null value
    if row[field_name] and constraints.primary_key ~= field_name and
      field_schema.type ~= "id" and row[field_name] ~= ngx_null then
      local names = utils_split(row[field_name], workspace_delimiter)
      if #names > 1 then
        row[field_name] = names[2]
      end
    end
  end

  if not include_ws then
    if table_name ~= "workspace_entities" then
      row.workspace_id = nil
    end
    row.workspace_name = nil
  end
  return row
end


-- true if the table is workspaceable and the workspace name is not
-- the wildcard - which should evaluate to all workspaces - and we are not
-- retrieving the default workspace itself
--
-- this is to break the cycle: some methods here - e.g., find_all -
-- need to retrieve the current workspace entity, which is set in
-- `before_filter`, but to set the entity some of those same methods are
-- used
function _M.is_workspaceable(table_name, ws_scope)
  return workspaceable[table_name] and #ws_scope > 0
end


local function encode_ws_list(ws_scope)
  local ids = {}
  for _, ws in ipairs(ws_scope) do
    ids[#ids + 1] = "'" .. tostring(ws.id) .. "'"
  end
  return table_concat(ids, ", ")
end


function _M.ws_scope_as_list(table_name)
  local ws_scope = get_workspaces()

  if workspaceable[table_name] and #ws_scope > 0 then
    return encode_ws_list(ws_scope)
  end
end


function _M.get_workspace()
  return ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
end


-- used to retrieve workspace specific configuration values.
-- * config must exist in default configuration or will result
--   in an error.
-- * if workspace specific config does not exist fall back to
--   default config value.
function _M.retrieve_ws_config(config_name, workspace)
  if workspace.config and workspace.config[config_name] ~= nil then
    return workspace.config[config_name]
  end

  return singletons.configuration[config_name]
end


function _M.build_ws_admin_gui_url(config, workspace)
  local admin_gui_url = config.admin_gui_url
  -- this will only occur when smtp_mock is on
  -- otherwise, conf_loader will throw an error if
  -- admin_gui_url is nil
  if not admin_gui_url then
    return ""
  end

  if not workspace.name or workspace.name == "" then
    return admin_gui_url
  end

  return admin_gui_url .. "/" .. workspace.name
end


function _M.build_ws_portal_gui_url(config, workspace)
  if not config.portal_gui_host
  or not config.portal_gui_protocol
  or not workspace.name then
    return config.portal_gui_host
  end

  if config.portal_gui_use_subdomains then
    return config.portal_gui_protocol .. '://' .. workspace.name .. '.' .. config.portal_gui_host
  end

  return config.portal_gui_protocol .. '://' .. config.portal_gui_host .. '/' .. workspace.name
end


function _M.build_ws_portal_cors_origins(workspace)
  -- portal_cors_origins takes precedence
  local portal_cors_origins = _M.retrieve_ws_config("portal_cors_origins", workspace)
  if portal_cors_origins and #portal_cors_origins > 0 then
    return portal_cors_origins
  end

   -- otherwise build origin from protocol, host and subdomain, if applicable
  local subdomain = ""
  local portal_gui_use_subdomains = _M.retrieve_ws_config("portal_gui_use_subdomains", workspace)
  if portal_gui_use_subdomains then
    subdomain = workspace.name .. "."
  end

  local portal_gui_protocol = _M.retrieve_ws_config("portal_gui_protocol", workspace)
  local portal_gui_host = _M.retrieve_ws_config("portal_gui_host", workspace)

  return { portal_gui_protocol .. "://" .. subdomain .. portal_gui_host }
end


return _M
