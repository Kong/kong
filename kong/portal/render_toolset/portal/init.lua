local helpers       = require "kong.portal.render_toolset.helpers"
local file_helpers  = require "kong.portal.file_helpers"
local workspaces    = require "kong.workspaces"
local singletons    = require "kong.singletons"
local ee            = require "kong.enterprise_edition"
local permissions   = require "kong.portal.permissions"
local looper        = require "kong.portal.render_toolset.looper"

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


local function get_all_specs()
  local render_ctx = singletons.render_ctx
  local developer = render_ctx.developer
  local ok, router_info = pcall(singletons.portal_router.introspect)
  if not ok then
    return {}
  end

  local workspace = workspaces.get_workspace()
  local ws_router = router_info.router[workspace.name]
  local ws_collection = ws_router.collection or {}

  local specs = {}
  for k, v in pairs(ws_collection) do
    if file_helpers.is_spec(v) then
      local headmatter = v.headmatter or {}
      local readable_by = headmatter.readable_by
      local has_permissions = type(readable_by) == "table" and #readable_by > 0
      local auth_required = has_permissions or readable_by == "*"
      local can_read = true
      if auth_required then
        can_read = permissions.can_read(developer, workspace.name, v.path)
      end
  
      if can_read then
        table.insert(specs, v)
      end
    end
  end

  return specs
end


local function get_specs_by_tag(_tag)
  local specs = get_all_specs()
    if not _tag then
      return specs
    end

    local filtered = {}
    for _, spec in ipairs(specs) do
      local parsed = spec.parsed or {}
      local tags = parsed.tags or {}

      for _, tag in ipairs(tags) do
        if type(tag) == "table" then
          tag = tag.name
        end
        
        if  string.lower(tag) == string.lower(_tag) then
          table.insert(filtered, spec)
        end
      end
    end

    return filtered
end


return function()
  local conf = singletons.configuration
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

  looper.set_node(portal)

  portal.workspace = workspace.name
  portal.url = portal_gui_url
  portal.specs = get_all_specs
  portal.specs_by_tag = get_specs_by_tag
  portal.developer_meta_fields = get_developer_meta_fields(workspace_conf)

  portal.files = function()
    return singletons.db.files:select_all()
  end

  if portal.api_url ~= "" and portal.api_url ~= nil then
    portal.api_url = portal.api_url .. '/' .. portal.workspace
  end

  return portal
end
