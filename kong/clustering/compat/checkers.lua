local ipairs = ipairs
local type = type


local ngx_log = ngx.log
local ngx_WARN = ngx.WARN


local LOG_PREFIX = "[clustering] "


local log_warn_message
do
  local fmt = string.format

  local KONG_VERSION = require("kong.meta").version

  log_warn_message = function(hint, action, dp_version, log_suffix)
    local msg = fmt("Kong Gateway v%s %s " ..
                    "which is incompatible with dataplane version %s " ..
                    "and will %s.",
                    KONG_VERSION, hint, dp_version, action)
    ngx_log(ngx_WARN, LOG_PREFIX, msg, log_suffix)
  end
end


local compatible_checkers = {
  { 3005000000, --[[ 3.5.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local has_update

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == 'opentelemetry' or plugin.name == 'zipkin' then
          local config = plugin.config
          if config.header_type == 'gcp' then
            config.header_type = 'preserve'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' header_type == gcp',
                             'overwritten with default value `preserve`',
                             dp_version, log_suffix)
            has_update = true
          end
        end

        if plugin.name == 'zipkin' then
          local config = plugin.config
          if config.default_header_type == 'gcp' then
            config.default_header_type = 'b3'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' default_header_type == gcp',
                             'overwritten with default value `b3`',
                             dp_version, log_suffix)
            has_update = true
          end
        end
      end

      return has_update
    end,
  },

  { 3004000000, --[[ 3.4.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local has_update

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == 'opentelemetry' or plugin.name == 'zipkin' then
          local config = plugin.config
          if config.header_type == 'aws' then
            config.header_type = 'preserve'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' header_type == aws',
                             'overwritten with default value `preserve`',
                             dp_version, log_suffix)
            has_update = true
          end
        end

        if plugin.name == 'zipkin' then
          local config = plugin.config
          if config.default_header_type == 'aws' then
            config.default_header_type = 'b3'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' default_header_type == aws',
                             'overwritten with default value `b3`',
                             dp_version, log_suffix)
            has_update = true
          end
        end
      end

      return has_update
    end,
  },

  { 3003000000, --[[ 3.3.0.0 ]]
    function(config)
      local has_update

      -- Support legacy queueing parameters for plugins that used queues prior to 3.3.  `retry_count` has been
      -- completely removed, so we always supply the default of 10 as that provides the same behavior as with a
      -- pre 3.3 CP.  The other queueing related legacy parameters can be determined from the new queue
      -- configuration table.
      for _, plugin in ipairs(config.plugins or {}) do
        local plugin_config = plugin.config
        if plugin.name == "statsd" or plugin.name == "datadog" then
          if type(plugin_config.retry_count) ~= "number" then
            plugin_config.retry_count = 10
            has_update = true
          end

          if type(plugin_config.queue_size) ~= "number" then
            if plugin_config.queue and type(plugin_config.queue.max_batch_size) == "number" then
              plugin_config.queue_size = plugin_config.queue.max_batch_size
              has_update = true

            else
              plugin_config.queue_size = 1
              has_update = true
            end
          end

          if type(plugin_config.flush_timeout) ~= "number" then
            if plugin_config.queue and type(plugin_config.queue.max_coalescing_delay) == "number" then
              plugin_config.flush_timeout = plugin_config.queue.max_coalescing_delay
              has_update = true

            else
              plugin_config.flush_timeout = 2
              has_update = true
            end
          end

        elseif plugin.name == "opentelemetry" then
          if type(plugin_config.batch_span_count) ~= "number" then
            if plugin_config.queue and type(plugin_config.queue.max_batch_size) == "number" then
              plugin_config.batch_span_count = plugin_config.queue.max_batch_size
              has_update = true

            else
              plugin_config.batch_span_count = 200
              has_update = true
            end
          end

          if type(plugin_config.batch_flush_delay) ~= "number" then
            if plugin_config.queue and type(plugin_config.queue.max_coalescing_delay) == "number" then
              plugin_config.batch_flush_delay = plugin_config.queue.max_coalescing_delay
              has_update = true

            else
              plugin_config.batch_flush_delay = 3
              has_update = true
            end
          end
        end -- if plugin.name
      end   -- for

      return has_update
    end,
  },

  { 3003000000, --[[ 3.3.0.0 ]]
    function(config)
      local has_update
      for _, config_entity in ipairs(config.vaults or {}) do
        if config_entity.name == "env" and type(config_entity.config) == "table" then
          local entity_config = config_entity.config
          local prefix = entity_config.prefix
          if type(prefix) == "string" then
            local new_prefix = prefix:gsub("-", "_")
            if new_prefix ~= prefix then
              entity_config.prefix = new_prefix
              has_update = true
            end
          end
        end
      end   -- for

      return has_update
    end,
  },

  { 3003000000, --[[ 3.3.0.0 ]]
    function(config, dp_version, log_suffix)
      -- remove updated_at field for core entities ca_certificates, certificates, consumers,
      -- targets, upstreams, plugins, workspaces, clustering_data_planes and snis
      local entity_names = {
        "ca_certificates", "certificates", "consumers", "targets", "upstreams",
        "plugins", "workspaces", "snis",
        }

      local has_update
      local updated_entities = {}

      for _, name in ipairs(entity_names) do
        for _, config_entity in ipairs(config[name] or {}) do
          if config_entity.updated_at then
            config_entity.updated_at = nil
            has_update = true
            if not updated_entities[name] then
              log_warn_message("contains configuration '" .. name .. ".updated_at'",
                               "be removed",
                               dp_version,
                               log_suffix)
              updated_entities[name] = true
            end
          end
        end
      end

      return has_update
    end
  },

  { 3002000000, --[[ 3.2.0.0 ]]
    function(config, dp_version, log_suffix)
      local config_services = config.services
      if not config_services  then
        return nil
      end

      local has_update
      for _, t in ipairs(config_services) do
        if t.protocol == "tls" then
          if t.client_certificate or t.tls_verify or
             t.tls_verify_depth   or t.ca_certificates
          then

            t.client_certificate = nil
            t.tls_verify = nil
            t.tls_verify_depth = nil
            t.ca_certificates = nil

            has_update = true
          end
        end
      end

      if has_update then
        log_warn_message("tls protocol service contains configuration 'service.client_certificate'" ..
                         "or 'service.tls_verify' or 'service.tls_verify_depth' or 'service.ca_certificates'",
                         "be removed",
                         dp_version,
                         log_suffix)
      end

      return has_update
    end
  },

  { 3002000000, --[[ 3.2.0.0 ]]
    function(config, dp_version, log_suffix)
      local config_upstreams = config.upstreams
      if not config_upstreams  then
        return nil
      end

      local has_update
      for _, t in ipairs(config_upstreams) do
        if t.algorithm == "latency" then
          t.algorithm = "round-robin"
          has_update = true
        end
      end

      if has_update then
        log_warn_message("configuration 'upstream.algorithm' contains 'latency' option",
                         "fall back to 'round-robin'",
                         dp_version,
                         log_suffix)
      end

      return has_update
    end
  },

  { 3002000000, --[[ 3.2.0.0 ]]
    function(config, dp_version, log_suffix)
      local config_plugins = config.plugins
      if not config_plugins then
        return nil
      end

      local has_update
      for _, plugin in ipairs(config_plugins) do
        if plugin.instance_name ~= nil then
          plugin.instance_name = nil
          has_update = true
        end
      end

      if has_update then
        log_warn_message("contains configuration 'plugin.instance_name'",
                         "be removed",
                         dp_version,
                         log_suffix)
      end

      return has_update
    end
  },

  { 3001000000, --[[ 3.1.0.0 ]]
    function(config, dp_version, log_suffix)
      local config_upstreams = config.upstreams
      if not config_upstreams then
        return nil
      end

      local has_update
      for _, t in ipairs(config_upstreams) do
        if t.use_srv_name ~= nil then
          t.use_srv_name = nil
          has_update = true
        end
      end

      if has_update then
        log_warn_message("contains configuration 'upstream.use_srv_name'",
                         "be removed",
                         dp_version,
                         log_suffix)
      end

      return has_update
    end
  },
}


return compatible_checkers
