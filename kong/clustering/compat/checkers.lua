local ipairs = ipairs


local log_warn_message
do
  local ngx_log = ngx.log
  local ngx_WARN = ngx.WARN
  local fmt = string.format

  local KONG_VERSION = require("kong.meta").version

  local _log_prefix = "[clustering] "

  log_warn_message = function(hint, action, dp_version, log_suffix)
    local msg = fmt("Kong Gateway v%s %s " ..
                    "which is incompatible with dataplane version %s " ..
                    "and will %s.",
                    KONG_VERSION, hint, dp_version, action)
    ngx_log(ngx_WARN, _log_prefix, msg, log_suffix)
  end
end


local compatible_checkers = {
  { 3003000000, --[[ 3.3.0.0 ]]
    function(config_table, dp_version, log_suffix)
      -- remove updated_at field for core entities ca_certificates, certificates, consumers,
      -- targets, upstreams, plugins, workspaces, clustering_data_planes and snis
      local entity_names = {
        "ca_certificates", "certificates", "consumers", "targets", "upstreams",
        "plugins", "workspaces", "clustering_data_planes", "snis",
        }

      local has_update
      local updated_entities = {}

      for _, name in ipairs(entity_names) do
        for _, config_entity in ipairs(config_table[name] or {}) do
          if config_entity["updated_at"] then

            config_entity["updated_at"] = nil

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
    function(config_table, dp_version, log_suffix)
      local config_services = config_table["services"]
      if not config_services  then
        return nil
      end

      local has_update
      for _, t in ipairs(config_services) do
        if t["protocol"] == "tls" then
          if t["client_certificate"] or t["tls_verify"] or
             t["tls_verify_depth"]   or t["ca_certificates"]
          then

            t["client_certificate"] = nil
            t["tls_verify"] = nil
            t["tls_verify_depth"] = nil
            t["ca_certificates"] = nil

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
    function(config_table, dp_version, log_suffix)
      local config_upstreams = config_table["upstreams"]
      if not config_upstreams  then
        return nil
      end

      local has_update
      for _, t in ipairs(config_upstreams) do
        if t["algorithm"] == "latency" then
          t["algorithm"] = "round-robin"
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
    function(config_table, dp_version, log_suffix)
      local config_plugins = config_table["plugins"]
      if not config_plugins then
        return nil
      end

      local has_update
      for _, plugin in ipairs(config_plugins) do
        if plugin["instance_name"] ~= nil then
          plugin["instance_name"] = nil
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
    function(config_table, dp_version, log_suffix)
      local config_upstreams = config_table["upstreams"]
      if not config_upstreams then
        return nil
      end

      local has_update
      for _, t in ipairs(config_upstreams) do
        if t["use_srv_name"] ~= nil then
          t["use_srv_name"] = nil
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
