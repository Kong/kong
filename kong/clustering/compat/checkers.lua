local ipairs = ipairs


local ngx = ngx
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN


local _log_prefix = "[clustering] "
local KONG_VERSION = require("kong.meta").version


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

      for _, name in ipairs(entity_names) do
        for _, config_entity in ipairs(config_table[name] or {}) do
          ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
            " contains configuration '" .. name .. ".updated_at'",
            " which is incompatible with dataplane version " .. dp_version .. " and will",
            " be removed.", log_suffix)
          config_entity.updated_at = nil
        end
      end
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
             t["tls_verify_depth"]   or t["ca_certificates"] then

            t["client_certificate"] = nil
            t["tls_verify"] = nil
            t["tls_verify_depth"] = nil
            t["ca_certificates"] = nil

            has_update = true
          end
        end
      end

      if has_update then
        ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                " tls protocol service contains configuration 'service.client_certificate'",
                " or 'service.tls_verify' or 'service.tls_verify_depth' or 'service.ca_certificates'",
                " which is incompatible with dataplane version " .. dp_version .. " and will",
                " be removed.", log_suffix)
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
        ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                " configuration 'upstream.algorithm' contain 'latency' option",
                " which is incompatible with dataplane version " .. dp_version .. " and will",
                " be fall back to 'round-robin'.", log_suffix)
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
        ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                " contains configuration 'plugin.instance_name'",
                " which is incompatible with dataplane version " .. dp_version,
                " and will be removed.", log_suffix)
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
        ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                " contains configuration 'upstream.use_srv_name'",
                " which is incompatible with dataplane version " .. dp_version,
                " and will be removed.", log_suffix)
      end

      return has_update
    end
  },
}


return compatible_checkers
