local plugin_config_iterator = require("kong.dao.migrations.helpers").plugin_config_iterator


return {
  {
    name = "2017-12-13-120000_tcp-log_tls",
    up = function(_, _, dao)
      for ok, config, update in plugin_config_iterator(dao, "tcp-log") do
        if not ok then
          return config
        end
				config.tls = false
				local ok, err = update(config)
				if not ok then
					return err
				end
      end
    end,
    down = function(_, _, dao) end  -- not implemented
  },
}

