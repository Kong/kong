-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local clone = require "table.clone"
local ee_utils = require "kong.enterprise_edition.utils"

local cjson_decode = cjson.decode
local null = ngx.null


local workspace_config = {}

function workspace_config.build_ws_admin_gui_url(config, workspace)
  local admin_gui_url = ee_utils.retrieve_admin_gui_url(config.admin_gui_url)

  if not workspace.name or workspace.name == "" then
    return admin_gui_url
  end

  return admin_gui_url .. "/" .. workspace.name
end


function workspace_config.build_ws_portal_gui_url(config, workspace)
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


function workspace_config.build_ws_portal_api_url(config)
  return config.portal_api_url
end


function workspace_config.build_ws_portal_cors_origins(workspace)
  -- portal_cors_origins takes precedence
  local portal_cors_origins = workspace_config.retrieve("portal_cors_origins", workspace)
  if portal_cors_origins and #portal_cors_origins > 0 then
    return portal_cors_origins
  end

  -- otherwise build origin from protocol, host and subdomain, if applicable
  local subdomain = ""
  local portal_gui_use_subdomains = workspace_config.retrieve("portal_gui_use_subdomains", workspace)
  if portal_gui_use_subdomains then
    subdomain = workspace.name .. "."
  end

  local portal_gui_protocol = workspace_config.retrieve("portal_gui_protocol", workspace)
  local portal_gui_host = workspace_config.retrieve("portal_gui_host", workspace)

  return { portal_gui_protocol .. "://" .. subdomain .. portal_gui_host }
end


-- used to retrieve workspace specific configuration values.
-- * config must exist in default configuration or will result
--   in an error.
-- * if workspace specific config does not exist fall back to
--   default config value.
-- * if 'opts.explicitly_ws' flag evaluates to true, workspace config
--   will be returned, even if it is nil/null
-- * if 'opts.decode_json' and conf is string, will decode and return table
function workspace_config.retrieve(config_name, workspace, opts)
  local conf
  opts = opts or {}

  if opts.explicitly_ws or workspace.config and
    workspace.config[config_name] ~= nil and
    workspace.config[config_name] ~= null then
    conf = workspace.config[config_name]
  else
    if _G.kong and kong.configuration then
      conf = kong.configuration[config_name]
    end
  end

  -- if table, return a copy so that we don't mutate the conf
  if type(conf) == "table" then
    return clone(conf)
  end

  if opts.decode_json and type(conf) == "string" then
    local json_conf, err = cjson_decode(conf)
    if err then
      return nil, err
    end

    return json_conf
  end

  return conf
end


return workspace_config
