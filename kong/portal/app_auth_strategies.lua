local GLOBAL_QUERY_OPTS = { workspace = ngx.null, show_ws_id = true }

return {
  ["kong-oauth2"] = {
    build_service_auth_config = function(service)
      local auth_config

      for plugin, err in kong.db.plugins:each(nil, GLOBAL_QUERY_OPTS) do
        if err then
          kong.log.err(err)
          break
        end
        if plugin.name == "oauth2" then
          if service.id == plugin.service.id then
            auth_config = {
              scopes = plugin.config.scopes,
              auth_header_name = plugin.config.auth_header_name,
              provision_key = plugin.config.provision_key,
              enable_implicit_grant = plugin.config.enable_implicit_grant,
              enable_password_grant = plugin.config.enable_password_grant,
              enable_client_credentials = plugin.config.enable_client_credentials,
              enable_authorization_code = plugin.config.enable_authorization_code,
            }
            break
          end
        end
      end

      return auth_config
    end
  },
  ["external-oauth2"] = {
    build_service_auth_config = function(service, app_reg_plugin)
      local auth_config = {}

      for plugin, err in kong.db.plugins:each(nil, GLOBAL_QUERY_OPTS) do
        if err then
          kong.log.err(err)
          break
        end
        if plugin.name == "openid-connect" then
          if service.id == plugin.service.id then
            auth_config.scopes = plugin.config.scopes
            auth_config.auth_methods = plugin.config.auth_methods
            if app_reg_plugin.config.show_issuer then
              auth_config.issuer = plugin.config.issuer
            end
            break
          end
        end
      end

      return auth_config
    end
  }
}
