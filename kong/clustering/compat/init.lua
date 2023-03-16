local cjson = require("cjson.safe")
local constants = require("kong.constants")
local meta = require("kong.meta")
local version = require("kong.clustering.compat.version")
local utils = require("kong.tools.utils")

local type = type
local ipairs = ipairs
local table_insert = table.insert
local table_sort = table.sort
local gsub = string.gsub
local deep_copy = utils.deep_copy
local split = utils.split
local deflate_gzip = utils.deflate_gzip
local cjson_encode = cjson.encode

local ngx = ngx
local ngx_log = ngx.log
local ngx_INFO = ngx.INFO
local ngx_NOTICE = ngx.NOTICE
local ngx_WARN = ngx.WARN

local version_num = version.string_to_number
local extract_major_minor = version.extract_major_minor

local _log_prefix = "[clustering] "

local REMOVED_FIELDS = require("kong.clustering.compat.removed_fields")
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local KONG_VERSION = meta.version


local _M = {}


local function check_kong_version_compatibility(cp_version, dp_version, log_suffix)
  local major_cp, minor_cp = extract_major_minor(cp_version)
  local major_dp, minor_dp = extract_major_minor(dp_version)

  if not major_cp then
    return nil, "data plane version " .. dp_version .. " is incompatible with control plane version",
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if not major_dp then
    return nil, "data plane version is incompatible with control plane version " ..
      cp_version .. " (" .. major_cp .. ".x.y are accepted)",
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if major_cp ~= major_dp then
    return nil, "data plane version " .. dp_version ..
      " is incompatible with control plane version " ..
      cp_version .. " (" .. major_cp .. ".x.y are accepted)",
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if minor_cp < minor_dp then
    return nil, "data plane version " .. dp_version ..
      " is incompatible with older control plane version " .. cp_version,
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if minor_cp ~= minor_dp then
    local msg = "data plane minor version " .. dp_version ..
      " is different to control plane minor version " ..
      cp_version

    ngx_log(ngx_INFO, _log_prefix, msg, log_suffix or "")
  end

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end


_M.check_kong_version_compatibility = check_kong_version_compatibility


function _M.plugins_list_to_map(plugins_list)
  local versions = {}
  for _, plugin in ipairs(plugins_list) do
    local name = plugin.name
    local major, minor = extract_major_minor(plugin.version)

    if major and minor then
      versions[name] = {
        major   = major,
        minor   = minor,
        version = plugin.version,
      }

    else
      versions[name] = {}
    end
  end
  return versions
end


function _M.check_version_compatibility(cp, dp)
  local dp_version, dp_plugin_map, log_suffix = dp.dp_version, dp.dp_plugins_map, dp.log_suffix

  local ok, err, status = check_kong_version_compatibility(KONG_VERSION, dp_version, log_suffix)
  if not ok then
    return ok, err, status
  end

  for _, plugin in ipairs(cp.plugins_list) do
    local name = plugin.name
    local cp_plugin = cp.plugins_map[name]
    local dp_plugin = dp_plugin_map[name]

    if not dp_plugin then
      if cp_plugin.version then
        ngx_log(ngx_WARN, _log_prefix, name, " plugin ", cp_plugin.version, " is missing from data plane", log_suffix)
      else
        ngx_log(ngx_WARN, _log_prefix, name, " plugin is missing from data plane", log_suffix)
      end

    else
      if cp_plugin.version and dp_plugin.version then
        local msg = "data plane " .. name .. " plugin version " .. dp_plugin.version ..
                    " is different to control plane plugin version " .. cp_plugin.version

        if cp_plugin.major ~= dp_plugin.major then
          ngx_log(ngx_WARN, _log_prefix, msg, log_suffix)

        elseif cp_plugin.minor ~= dp_plugin.minor then
          ngx_log(ngx_INFO, _log_prefix, msg, log_suffix)
        end

      elseif dp_plugin.version then
        ngx_log(ngx_NOTICE, _log_prefix, "data plane ", name, " plugin version ", dp_plugin.version,
                        " has unspecified version on control plane", log_suffix)

      elseif cp_plugin.version then
        ngx_log(ngx_NOTICE, _log_prefix, "data plane ", name, " plugin version is unspecified, ",
                        "and is different to control plane plugin version ",
                        cp_plugin.version, log_suffix)
      end
    end
  end

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end


function _M.check_configuration_compatibility(cp, dp)
  for _, plugin in ipairs(cp.plugins_list) do
    if cp.plugins_configured[plugin.name] then
      local name = plugin.name
      local cp_plugin = cp.plugins_map[name]
      local dp_plugin = dp.dp_plugins_map[name]

      if not dp_plugin then
        if cp_plugin.version then
          return nil, "configured " .. name .. " plugin " .. cp_plugin.version ..
                      " is missing from data plane", CLUSTERING_SYNC_STATUS.PLUGIN_SET_INCOMPATIBLE
        end

        return nil, "configured " .. name .. " plugin is missing from data plane",
               CLUSTERING_SYNC_STATUS.PLUGIN_SET_INCOMPATIBLE
      end

      if cp_plugin.version and dp_plugin.version then
        -- CP plugin needs to match DP plugins with major version
        -- CP must have plugin with equal or newer version than that on DP

        if cp_plugin.major ~= dp_plugin.major or
          cp_plugin.minor < dp_plugin.minor then
          local msg = "configured data plane " .. name .. " plugin version " .. dp_plugin.version ..
                      " is different to control plane plugin version " .. cp_plugin.version
          return nil, msg, CLUSTERING_SYNC_STATUS.PLUGIN_VERSION_INCOMPATIBLE
        end
      end
    end
  end

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end


local split_field_name
do
  local cache = {}

  --- a.b.c => { "a", "b", "c" }
  ---
  ---@param name string
  ---@return string[]
  function split_field_name(name)
    local fields = cache[name]
    if fields then
      return fields
    end

    fields = split(name, ".")

    for _, part in ipairs(fields) do
      assert(part ~= "", "empty segment in field name: " .. tostring(name))
    end

    cache[name] = fields
    return fields
  end
end


---@param t table
---@param key string
---@return boolean deleted
local function delete_at(t, key)
  local ref = t
  if type(ref) ~= "table" then
    return false
  end

  local addr = split_field_name(key)
  local len = #addr
  local last = addr[len]

  for i = 1, len - 1 do
    ref = ref[addr[i]]
    if type(ref) ~= "table" then
      return false
    end
  end

  if ref[last] ~= nil then
    ref[last] = nil
    return true
  end

  return false
end


local function rename_field(config, name_from, name_to, has_update)
  if config[name_from] ~= nil then
    config[name_to] = config[name_from]
    config[name_from] = nil
    return true
  end
  return has_update
end


local function invalidate_keys_from_config(config_plugins, keys, log_suffix, dp_version_num)
  if not config_plugins then
    return false
  end

  local has_update

  for _, t in ipairs(config_plugins) do
    local config = t and t["config"]
    if config then
      local name = gsub(t["name"], "-", "_")
      if keys[name] ~= nil then
        -- Any dataplane older than 3.2.0
        if dp_version_num < 3002000000 then
          -- OSS
          if name == "session" then
            has_update = rename_field(config, "idling_timeout", "cookie_idletime", has_update)
            has_update = rename_field(config, "rolling_timeout", "cookie_lifetime", has_update)
            has_update = rename_field(config, "stale_ttl", "cookie_discard", has_update)
            has_update = rename_field(config, "cookie_same_site", "cookie_samesite", has_update)
            has_update = rename_field(config, "cookie_http_only", "cookie_httponly", has_update)
            has_update = rename_field(config, "remember", "cookie_persistent", has_update)

            if config["cookie_samesite"] == "Default" then
              config["cookie_samesite"] = "Lax"
            end
          end
        end

        for _, key in ipairs(keys[name]) do
          if delete_at(config, key) then
            ngx_log(ngx_WARN, _log_prefix, name, " plugin contains configuration '", key,
              "' which is incompatible with dataplane and will be ignored", log_suffix)
            has_update = true
          end
        end
      end
    end
  end

  return has_update
end


local get_removed_fields
do
  local cache = {}

  function get_removed_fields(dp_version)
    local plugin_fields = cache[dp_version]
    if plugin_fields ~= nil then
      return plugin_fields or nil
    end

    -- Merge dataplane unknown fields; if needed based on DP version
    for ver, plugins in pairs(REMOVED_FIELDS) do
      if dp_version < ver then
        for plugin, items in pairs(plugins) do
          plugin_fields = plugin_fields or {}
          plugin_fields[plugin] = plugin_fields[plugin] or {}

          for _, name in ipairs(items) do
            table_insert(plugin_fields[plugin], name)
          end
        end
      end
    end

    if plugin_fields then
      -- sort for consistency
      for _, list in pairs(plugin_fields) do
        table_sort(list)
      end
      cache[dp_version] = plugin_fields
    else
      -- explicit negative cache
      cache[dp_version] = false
    end

    return plugin_fields
  end

  -- expose for unit tests
  _M._get_removed_fields = get_removed_fields
  _M._set_removed_fields = function(fields)
    local saved = REMOVED_FIELDS
    REMOVED_FIELDS = fields
    cache = {}
    return saved
  end
end


-- returns has_update, modified_deflated_payload, err
function _M.update_compatible_payload(payload, dp_version, log_suffix)
  local cp_version_num = version_num(KONG_VERSION)
  local dp_version_num = version_num(dp_version)

  -- if the CP and DP have the same version, avoid the payload
  -- copy and compatibility updates
  if cp_version_num == dp_version_num then
    return false
  end

  local has_update
  payload = deep_copy(payload, false)
  local config_table = payload["config_table"]

  local fields = get_removed_fields(dp_version_num)
  if fields then
    if invalidate_keys_from_config(config_table["plugins"], fields, log_suffix, dp_version_num) then
      has_update = true
    end
  end

  if dp_version_num < 3003000000 --[[ 3.3.0.0 ]] then
    -- remove updated_at field for core entities ca_certificates, certificates, consumers,
    -- targets, upstreams, plugins, workspaces, clustering_data_planes and snis
    local entity_names = {'ca_certificates', 'certificates', 'consumers', 'targets', 'upstreams',
      'plugins', 'workspaces', 'clustering_data_planes', 'snis'}

    for _, name in ipairs(entity_names) do
      for _, config_entity in ipairs(config_table[name] or {}) do
        if config_entity["updated_at"] ~= nil then
          ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
            " contains configuration '" .. name .. ".updated_at'",
            " which is incompatible with dataplane version " .. dp_version .. " and will",
            " be removed.", log_suffix)
          config_entity["updated_at"] = nil
          has_update = true
        end
      end
    end
  end

  if dp_version_num < 3002000000 --[[ 3.2.0.0 ]] then
    local config_plugins = config_table["plugins"]
    if config_plugins then
      for _, plugin in ipairs(config_plugins) do
        if plugin["instance_name"] ~= nil then
          ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
            " contains configuration 'plugin.instance_name'",
            " which is incompatible with dataplane version " .. dp_version .. " and will",
            " be removed.", log_suffix)
          plugin["instance_name"] = nil
          has_update = true
        end
      end
    end

    local config_services = config_table["services"]
    if config_services then
      for _, t in ipairs(config_services) do
        if t["protocol"] == "tls" then
          if t["client_certificate"] or t["tls_verify"]
              or t["tls_verify_depth"] or t["ca_certificates"] then
            ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                      " tls protocol service contains configuration 'service.client_certificate'",
                      " or 'service.tls_verify' or 'service.tls_verify_depth' or 'service.ca_certificates'",
                      " which is incompatible with dataplane version " .. dp_version .. " and will",
                      " be removed.", log_suffix)
            t["client_certificate"] = nil
            t["tls_verify"] = nil
            t["tls_verify_depth"] = nil
            t["ca_certificates"] = nil
            has_update = true
          end
        end
      end
    end

    local config_upstreams = config_table["upstreams"]
    if config_upstreams then
      for _, t in ipairs(config_upstreams) do
        if t["algorithm"] == "latency" then
          ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                  " configuration 'upstream.algorithm' contain 'latency' option",
                  " which is incompatible with dataplane version " .. dp_version .. " and will",
                  " be fall back to 'round-robin'.", log_suffix)
          t["algorithm"] = "round-robin"
          has_update = true
        end
      end
    end
  end


  if dp_version_num < 3001000000 --[[ 3.1.0.0 ]] then
    local config_upstream = config_table["upstreams"]
    if config_upstream then
      for _, t in ipairs(config_upstream) do
        if t["use_srv_name"] ~= nil then
          ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                  " contains configuration 'upstream.use_srv_name'",
                  " which is incompatible with dataplane version " .. dp_version .. " and will",
                  " be removed.", log_suffix)
          t["use_srv_name"] = nil
          has_update = true
        end
      end
    end
  end

  if has_update then
    local deflated_payload, err = deflate_gzip(cjson_encode(payload))
    if deflated_payload then
      return true, deflated_payload

    else
      return true, nil, err
    end
  end

  return false, nil, nil
end


return _M
