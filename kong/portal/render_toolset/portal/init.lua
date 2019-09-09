local helpers       = require "kong.portal.render_toolset.helpers"
local workspaces    = require "kong.workspaces"
local singletons    = require "kong.singletons"
local ee            = require "kong.enterprise_edition"

local function parse_developer_field(item)
  local SCHEMA_TO_FIELD_TYPE = { string = "text", number = "number" }
  local type = item.is_email and "email" or SCHEMA_TO_FIELD_TYPE[item.validator.type]

  return {
    name = item.title,
    label = item.label,
    required = item.validator.required,
    type = type,
  }
end


local function get_developer_meta_fields(conf)
  local fields = helpers.json_decode(conf.PORTAL_DEVELOPER_META_FIELDS)
  return helpers.map(fields, parse_developer_field)
end


local function get_all_specs(files)
  local specs = files or {}

  specs = helpers.filter(specs, helpers.is_spec)
  specs = helpers.map(specs, helpers.parse_spec)

  return specs
end


return function()
  local conf = singletons.configuration
  local files = singletons.db.files:select_all()
  local render_ctx = singletons.render_ctx
  local workspace = workspaces.get_workspace()
  local workspace_conf = ee.prepare_portal(render_ctx, singletons.configuration)
  local portal_gui_url = workspaces.build_ws_portal_gui_url(conf, workspace)
  local portal = helpers.tbl.deepcopy(render_ctx.portal or {})

  -- Add any fields that might have been missed
  for k, v in pairs(workspace_conf) do
    local is_portal = string.sub(k, 1, 7) == "PORTAL_"
    local key = string.lower(string.sub(k, 8, #k))
    if is_portal and portal[key] == nil then
      portal[key] = v
    end
  end

  portal.files = files
  portal.specs = get_all_specs(files)
  portal.workspace = workspace.name
  portal.developer_meta_fields = get_developer_meta_fields(workspace_conf)
  portal.url = portal_gui_url

  if portal.api_url ~= "" and portal.api_url ~= nil then
    portal.api_url = portal.api_url .. '/' .. portal.workspace
  end

  return portal
end
