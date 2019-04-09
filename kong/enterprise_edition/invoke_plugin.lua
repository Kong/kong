local utils = require "kong.tools.utils"

local tostring     = tostring
local type         = type

local SERVICE_IDS = {
  portal = "00000000-0000-0000-0000-000000000000",
  admin =  "00000000-0000-0000-0000-000000000001",
}

local loaded_plugins_map = {}
local admin_plugin_models = {}
local PHASES, set_phase, set_named_ctx

local function apply_plugin(plugin, phase, opts)
  set_phase(kong, PHASES[phase])
  set_named_ctx(kong, "plugin", plugin.config)

  local err = coroutine.wrap(plugin.handler[phase])(plugin.handler, plugin.config)
  if err then
    return nil, err
  end

  if opts.api_type == "admin" then
    set_phase(kong, PHASES.admin_api)
  end

  if opts.api_type == "portal" then
    set_phase(kong, PHASES.access)
  end

  return true
end

local function prepare_plugin(opts)
  local model, err

  local plugin = loaded_plugins_map[opts.name]
  if not plugin then
    return nil, "plugin: " .. opts.name .. " not found."
  end

  local fields = {
    name = opts.name,
    service = { id = SERVICE_IDS[opts.api_type], },
    config = utils.deep_copy(opts.config or {}),
  }

  if opts.api_type == "admin" then
    model = admin_plugin_models[opts.name]
  end

  if not model then
    -- convert plugin configuration over to model to obtain defaults
    local plugins_entity = opts.db.plugins
    model, err = plugins_entity.schema:process_auto_fields(fields, "insert")
    if not model then
      local err_t = plugins_entity.errors:schema_violation(err)
      return nil, tostring(err_t), err_t
    end

     -- only cache valid models
    local ok, errors = plugins_entity.schema:validate_insert(model)
    if not ok then
      -- this config is invalid -- return errors until the user fixes
      local err_t = plugins_entity.errors:schema_violation(errors)
      return nil, tostring(err_t), err_t
    end

    -- convert <userdata> to nil
    for k, v in pairs(model.config) do
      if type(v) == "userdata" then
        model.config[k] = nil
      end
    end

    if opts.api_type == "admin" then
      admin_plugin_models[opts.name] = model
    end
  end

  return {
    handler = plugin.handler,
    config = model.config,
  }
end


local function prepare_and_invoke(opts)
  local prepared_plugin, err = prepare_plugin(opts)
  if not prepared_plugin then
    return nil, err
  end

  local ok, err
  for _, phase in ipairs(opts.phases) do
    ok, err = apply_plugin(prepared_plugin, phase, opts)
    if not ok then
      return nil, err
    end
  end

  return true
end

return {
  new = function(opts)
    for _, plugin in ipairs(opts.loaded_plugins) do
      loaded_plugins_map[plugin.name] = plugin
    end

    local kong_global = opts.kong_global

    PHASES = kong_global.phases
    set_phase = kong_global.set_phase
    set_named_ctx = kong_global.set_named_ctx

    return setmetatable({}, {
      __call = function(_, ...)
        return prepare_and_invoke(...)
      end,
    })
  end
}
