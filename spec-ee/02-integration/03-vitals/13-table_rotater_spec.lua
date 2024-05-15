-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key
local ngx_time = ngx.time
local tonumber = tonumber
local max = math.max
local unpack = unpack


local function select_vitals_seconds_tables(db)
  local query = [[
  select table_name from information_schema.tables
   where table_name like 'vitals_stats_seconds_%'
  ]]

  local res = assert(db:query(query))
  return res
end


for _, strategy in helpers.each_strategy() do
  describe("vitals table rotater #" .. strategy, function()
    local reset_license_data, db

    lazy_setup(function()
      reset_license_data = clear_license_env()
      local _
      _, db = helpers.get_db_utils(strategy, {
        "clustering_data_planes",
        "licenses",
      })
      db = db.connector

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        log_level = "notice",
        license_path = "spec-ee/fixtures/mock_license.json",
        portal_and_vitals_key = get_portal_and_vitals_key(),
        vitals = true,
        vitals_ttl_seconds = 2,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot")
      helpers.stop_kong("servroot2")
      reset_license_data()
    end)

    it("only init in control plane init worker phase", function()
      assert.logfile("servroot/logs/error.log").has.line("[vitals-table-rotater] init vitals table rotater, context: init_worker_by_lua", true, 1)

      helpers.clean_logfile("servroot/logs/error.log")

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:19002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        log_level = "info",
        vitals_flush_interval = 1,
        license_path = "spec-ee/fixtures/mock_license.json",
        portal_and_vitals_key = get_portal_and_vitals_key(),
        vitals = true,
      }))

      -- check if vitals table rotater init trigger by dataplane connect
      assert.logfile("servroot/logs/error.log").has.no.line("init vitals table rotater, context: ngx.timer", true, 5)

      local res = select_vitals_seconds_tables(db)
      local seconds_times = {}
      local seconds_table_prefix = "vitals_stats_seconds_"
      for i = 1, #res do
        seconds_times[i] = tonumber(res[i].table_name:sub(#seconds_table_prefix + 1))
      end

      local nearly_table_time = max(unpack(seconds_times))
      local now = ngx_time()
      -- verify that table rotater timer work(table rotater timer should create new table every 2s during ngx.sleep(5))
      assert.is_true(now - nearly_table_time < 3)
    end)
  end)
end
