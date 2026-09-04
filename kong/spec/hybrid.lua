------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.hybrid

local helpers = require("spec.helpers")
local kong_table = require("kong.tools.table")
local reload_module = require("spec.internal.module").reload
local assert = require("luassert")
local asserts = reload_module("spec.internal.asserts") -- luacheck: ignore
local conf = require("spec.internal.conf")

local function get_patched_helpers(strategy, deploy, rpc, rpc_sync, opts)
  local helpers = require("spec.helpers")

  local _M = {}
  local _prefix = nil

  _M.data_plane = nil
  _M.control_plane = nil

  function _M.start_kong(env, tables, preserve_prefix, fixtures)
    local ret, v
    if deploy == "traditional" then
      ret, v = helpers.start_kong(env, tables, preserve_prefix, fixtures)
      if ret then
        _prefix = env.prefix or conf.prefix
      end
      _M.data_plane = helpers.get_running_conf(_prefix)

    else
      local hybrid_envs = {
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_rpc = rpc,
        cluster_rpc_sync = rpc_sync,
        prefix = "",
        role = "",
        cluster_listen = "",
        cluster_telemetry_listen = "",
        cluster_control_plane = "",
        cluster_telemetry_endpoint = "",
      }

      for k, v in pairs(hybrid_envs) do
        assert.is_nil(env[k], "can't specify " .. k .. " in env of start_kong in hybrid mode")
      end

      if env.database then
        assert.equal(env.database, strategy, "database must be the same as strategy in hybrid mode")
      end

      local cp_envs = kong_table.deep_merge(env, hybrid_envs)
      cp_envs.database = strategy
      cp_envs.role = "control_plane"
      cp_envs.prefix = "servroot"
      cp_envs.cluster_listen = "127.0.0.1:9005"
      cp_envs.cluster_telemetry_listen = "127.0.0.1:9006"
      cp_envs.cluster_control_plane = nil
      cp_envs.cluster_telemetry_endpoint = nil

      assert(helpers.start_kong(cp_envs, tables, preserve_prefix, fixtures))

      local dp_envs = kong_table.deep_merge(env, hybrid_envs)
      dp_envs.database = "off"
      dp_envs.role = "data_plane"
      dp_envs.prefix = "servroot2"
      dp_envs.cluster_control_plane = "127.0.0.1:9005"
      dp_envs.cluster_telemetry_endpoint = "127.0.0.1:9006"
      dp_envs.cluster_listen = nil
      dp_envs.cluster_telemetry_listen = nil

      assert(helpers.start_kong(dp_envs, nil, preserve_prefix, nil))

      _M.control_plane = helpers.get_running_conf("servroot")
      _M.data_plane = helpers.get_running_conf("servroot2")

      if rpc_sync == "on" and not opts.dont_wait_full_sync then
        assert.logfile(_M.data_plane.nginx_err_logs).has.line("[kong.sync.v2] full sync ends", true, 10)
      end

      ret = true
    end

    if strategy ~= "off" then
      -- this helpers function doesn't support DB-less mode
      _M.wait_for_all_config_update()
    end

    return ret, v
  end

  function _M.stop_kong(prefix, preserve_prefix, preserve_dc, signal, nowait)
    local ret, v

    if deploy == "hybrid" then
      assert.is_nil(prefix, "can't specify prefix in hybrid mode")
      ret = helpers.stop_kong("servroot", preserve_prefix, preserve_dc, signal, nowait)
      if ret then
        ret = helpers.stop_kong("servroot2", preserve_prefix, preserve_dc, signal, nowait)
      end

    else
      ret, v= helpers.stop_kong(prefix, preserve_prefix, preserve_dc, signal, nowait)
    end

    _prefix = nil
    _M.control_plane = nil
    _M.data_plane = nil

    return ret, v
  end

  function _M.clean_logfile(logfile)
    if not logfile and deploy == "hybrid" then
      helpers.clean_logfile(helpers.get_running_conf("servroot").nginx_err_logs)
      helpers.clean_logfile(helpers.get_running_conf("servroot2").nginx_err_logs)

    else
      helpers.clean_logfile(logfile)
    end
  end

  function _M.get_prefix_for(role)
    if deploy == "hybrid" then
      role = role or "data_plane"
      if role == "data_plane" then
        return "servroot2"
      else
        return "servroot"
      end
    else
      return _prefix
    end
  end

  function _M.wait_for_all_config_update(wait_opts)
    if strategy ~= "off" then
      local copied_opts = kong_table.deep_copy(wait_opts) or {}

      -- this helpers function doesn't support DB-less mode
      helpers.wait_for_all_config_update(copied_opts)
    end
  end

  function _M.format_tags()
    local tags = "#" .. strategy .. " #" .. deploy
    if rpc == "on" then
      tags = tags .. " #rpc"
    end
    if rpc_sync == "on" then
      tags = tags .. " #rpc_sync"
    end
    return tags
  end

  function _M.reload_helpers()
    return get_patched_helpers(strategy, deploy, rpc, rpc_sync, opts)
  end

  return setmetatable(_M, { __index = helpers })
end


-- Run tests in different deployment topologies
-- @function run_for_each_deploy
-- @param opts (optional table) options for the runner
-- @param fn (function) test routine, receiving helpers, strategy, deploy, rpc, and rpc_sync
-- @return nil
--
-- This function is used to run tests across different deployment topologies.
-- It accepts an optional options table and a test function.
-- The options table can contain custom configurations, while the test function
-- will be called for each combination of strategy and deployment.
--
-- The test is run as follows:
-- 1. Iterates over each strategy obtained from opts.strategies_iterator() or helpers.each_strategy().
-- 2. For each strategy, iterates over two deployment types: "traditional" and "hybrid".
-- 3. For each deployment type, iterates over three RPC and RPC sync combinations: {"off", "off"}, {"on", "off"}, {"on", "on"}.
-- 4. For each combination, calls the test function fn, passing helpers, strategy, deploy, rpc, and rpc_sync as parameters.
--
-- opts: (table) custom configurations
--   - dont_wait_full_sync: (boolean) if true, the function won't wait for full sync to complete
--   - strategies_iterator: (function) If present, this function will be used to iterate over strategies.
--
-- The helpers passed into test function is a patched version of spec.helpers.
-- It contains the following modified functions and limitions:
-- - start_kong: will start Kong in hybrid mode if deploy is "hybrid"
-- - stop_kong: will stop Kong in hybrid mode if deploy is "hybrid"
-- - clean_logfile: will clean the logfile for hybrid deployment if deploy is "hybrid"
-- - get_prefix_for: will return the prefix for the specified role
-- - wait_for_all_config_update: will wait for all config updates to complete
-- - format_tags: will return a formatted string with deployment tags
-- - reload_helpers: will return a new helpers module
-- The original parameter will be passed as is to the original helpers functions.
-- Except in hybrid mode, there're some critical options that can't be specified
-- in the env table of start_kong. If these options are specified, the function will
-- raise an error. Additionally, all prefix options are not available in hybrid mode.
--
-- Additionally, patched helpers will contains following tables:
-- - data_plane: the running configuration of the data plane (or instance of traditional mode)
-- - control_plane: the running configuration of the control plane (only in hybrid mode)
local function run_for_each_deploy(opts, fn)
  opts = opts or {}
  local strategies_iterator = opts.strategies_iterator or helpers.each_strategy

  for _, strategy in strategies_iterator() do
  for _, deploy in ipairs({ "traditional", "hybrid" }) do
  for _, v in ipairs({ {"off", "off"}, {"on", "off"}, {"on", "on"}, }) do
    local rpc, rpc_sync = v[1], v[2]

    if strategy == "off" then
      if deploy == "hybrid" then
        -- DB-less mode doesn't support hybrid deployments
        goto continue
      end

      if not (rpc == "off" and rpc_sync == "off") then
        -- no need to test this combination in DB-less deployments
        -- so only test DB-less once
        goto continue
      end
    end

    if deploy == "traditional" and not (rpc == "off" and rpc_sync == "off") then
      -- no need to test this combination in traditional deployments
      -- so only test traditional once
      goto continue
    end

    local helpers = get_patched_helpers(strategy, deploy, rpc, rpc_sync, opts)

    -- Test body begins here
    fn(helpers, strategy, deploy, rpc, rpc_sync)
    -- Test body ends here

    ::continue::
  end -- for _, v in ipairs({ {"off", "off"}, {"on", "off"}, {"on", "on"}, }) do
  end -- for _, deploy in ipairs({ "traditional", "hybrid" }) do
  end -- for _, strategy in helpers.each_strategy() do
end

return {
  run_for_each_deploy = run_for_each_deploy,
}
