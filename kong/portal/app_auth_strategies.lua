-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"

local function build_auth_config(plugin_name, query_handler, build_handler)
  local auth_config
  local options = { workspace = ngx.null, show_ws_id = true, search_fields = { name = plugin_name } }
  for plugin, err in query_handler(options) do
    if err then
      kong.log.err(err)
      break
    end
    if plugin.enabled then
      auth_config = build_handler(plugin)
      break
    end
  end

  return auth_config
end

local build_plugin_config = {
  ["key-auth"] = function(plugin)
    return {
      key_in_body = plugin.config.key_in_body,
      key_names = setmetatable(plugin.config.key_names, cjson.empty_array_mt),
      run_on_preflight = plugin.config.run_on_preflight,
    }
  end,
  ["oauth2"] = function(plugin)
    return {
      scopes = plugin.config.scopes,
      auth_header_name = plugin.config.auth_header_name,
      provision_key = plugin.config.provision_key,
      enable_implicit_grant = plugin.config.enable_implicit_grant,
      enable_password_grant = plugin.config.enable_password_grant,
      enable_client_credentials = plugin.config.enable_client_credentials,
      enable_authorization_code = plugin.config.enable_authorization_code,
    }
  end,
  ["openid-connect"] = function(plugin, app_reg_plugin)
    local config = {}
    config.scopes = plugin.config.scopes
    config.auth_methods = plugin.config.auth_methods
    if app_reg_plugin.config.show_issuer then
      config.issuer = plugin.config.issuer
    end

    return config
  end
}

return {
  ["kong-oauth2"] = {
    build_service_auth_config = function(service)
      
      return build_auth_config("key-auth", function(options)
            return kong.db.plugins:each_for_service(service, nil, options)
          end, build_plugin_config["key-auth"])
          or
          build_auth_config("oauth2", function(options)
            return kong.db.plugins:each_for_service(service, nil, options)
          end, build_plugin_config["oauth2"]) or {}
    end
  },

  ["external-oauth2"] = {
    build_service_auth_config = function(service, app_reg_plugin)
      local function build_config(plugin)
        return build_plugin_config["openid-connect"](plugin, app_reg_plugin)
      end

      return build_auth_config("openid-connect", function(options)
        return kong.db.plugins:each_for_service(service, nil, options)
      end, build_config) or {}
    end
  }
}
