local plugin_config_iterator = require("kong.dao.migrations.helpers").plugin_config_iterator

return {
  {
    name = "2017-10-23-150900_header_type_default",
    up = function(_, _, dao)
      for ok, config, update in plugin_config_iterator(dao, "ldap-auth") do
        if not ok then
          return config
        end
        if config.header_type == nil then
          config.header_type = "ldap"
          local _, err = update(config)
          if err then
            return err
          end
        end
      end
    end,
    down = function(_, _, dao) end  -- not implemented
  },
}
