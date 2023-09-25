local constants = require("kong.constants")
local meta = require("kong.meta")
local version = require("kong.clustering.compat.version")
local utils = require("kong.tools.utils")


local type = type
local pairs = pairs
local ipairs = ipairs
local table_concat = table.concat
local table_insert = table.insert
local table_sort = table.sort
local gsub = string.gsub
local split = utils.split


local ngx = ngx
local ngx_log = ngx.log
local ngx_INFO = ngx.INFO
local ngx_NOTICE = ngx.NOTICE
local ngx_WARN = ngx.WARN


local version_num = version.string_to_number
local extract_major_minor = version.extract_major_minor


local LOG_PREFIX = "[clustering] "


local REMOVED_FIELDS = require("kong.clustering.compat.removed_fields")
local COMPATIBILITY_CHECKERS = require("kong.clustering.compat.checkers")
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local KONG_VERSION = meta.version
local KONG_VERSION_NUM = version_num(KONG_VERSION)


local EMPTY = {}


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

    ngx_log(ngx_INFO, LOG_PREFIX, msg, log_suffix or "")
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
        ngx_log(ngx_WARN, LOG_PREFIX, name, " plugin ", cp_plugin.version, " is missing from data plane", log_suffix)
      else
        ngx_log(ngx_WARN, LOG_PREFIX, name, " plugin is missing from data plane", log_suffix)
      end

    else
      if cp_plugin.version and dp_plugin.version then
        local msg = "data plane " .. name .. " plugin version " .. dp_plugin.version ..
                    " is different to control plane plugin version " .. cp_plugin.version

        if cp_plugin.major ~= dp_plugin.major then
          ngx_log(ngx_WARN, LOG_PREFIX, msg, log_suffix)

        elseif cp_plugin.minor ~= dp_plugin.minor then
          ngx_log(ngx_INFO, LOG_PREFIX, msg, log_suffix)
        end

      elseif dp_plugin.version then
        ngx_log(ngx_NOTICE, LOG_PREFIX, "data plane ", name, " plugin version ", dp_plugin.version,
                        " has unspecified version on control plane", log_suffix)

      elseif cp_plugin.version then
        ngx_log(ngx_NOTICE, LOG_PREFIX, "data plane ", name, " plugin version is unspecified, ",
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

  if cp.conf.wasm then
    local dp_filters = dp.filters or EMPTY
    local missing
    for name in pairs(cp.filters or EMPTY) do
      if not dp_filters[name] then
        missing = missing or {}
        table_insert(missing, name)
      end
    end

    if missing then
      local msg = "data plane is missing one or more wasm filters "
                  .. "(" .. table_concat(missing, ", ") .. ")"
      return nil, msg, CLUSTERING_SYNC_STATUS.FILTER_SET_INCOMPATIBLE
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
            ngx_log(ngx_WARN, LOG_PREFIX, name, " plugin contains configuration '", key,
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
  local dp_version_num = version_num(dp_version)

  -- if the CP and DP have the same version, avoid the payload
  -- copy and compatibility updates
  if KONG_VERSION_NUM == dp_version_num then
    return payload
  end

  payload = utils.cycle_aware_deep_copy(payload, true)

  for _, checker in ipairs(COMPATIBILITY_CHECKERS) do
    local ver = checker[1]
    local fn  = checker[2]
    if dp_version_num < ver then
      fn(payload.config, dp_version, log_suffix)
    end
  end

  local fields = get_removed_fields(dp_version_num)
  if fields then
    invalidate_keys_from_config(payload.config.plugins, fields, log_suffix, dp_version_num)
  end

  return payload
end


return _M
