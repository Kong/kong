-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local UNLICENSED = "UNLICENSED"

local function get_report(client)
  local res = client:get("/license/report")
  assert.res_status(200, res)
  return assert.response(res).has.jsonbody()
end

local function json(body)
  return {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = cjson.encode(body),
  }
end

local function await_license(client, key, msg)
  assert
    .with_timeout(15)
    .with_step(0.1)
    .eventually(function()
      local report = get_report(client)
      assert.is_table(report, "malformed license report")
      assert.is_table(report.license, "malformed license report")
      assert.is_string(report.license.license_key, "malformed license report")
      return report.license.license_key == key, report
    end)
    .is_truthy(msg)
end

local function check_ee_plugin(client, msg, header_name, header_value)
  header_name = header_name or "x-test"
  header_value = header_value or "123"

  assert
    .with_timeout(15)
    .with_step(0.1)
    .eventually(function()
      local res = client:get("/test")
      assert.equals(200, res.status, "non-200 status code")
      local body = assert.is_string(res:read_body(), "failed reading response")
      local req = cjson.decode(body)

      assert.is_table(req.headers, "missing request headers")

      -- confirm that we went through request-transformer-advanced
      local value = req.headers[header_name]
      if not value then
        return nil, { header = header_name,
                      message = "header not found",
                    }

      elseif value ~= header_value then
        return nil, { header = header_name,
                      expected = header_value,
                      actual = value,
                    }
      end

      return true
    end)
    .is_truthy(msg)
end

local function check_ee_plugin_neg(client, msg, header_name, header_value)
  header_name = header_name or "x-test"
  header_value = header_value or "123"

  local headers

  -- getting a valid response is eventually consistent, but the negative
  -- condition is not
  assert
    .with_timeout(15)
    .with_step(0.1)
    .eventually(function()
      local res = client:get("/test")
      assert.equals(200, res.status, "non-200 status code")
      local body = assert.is_string(res:read_body(), "failed reading response")
      local req = cjson.decode(body)
      headers = assert.is_table(req.headers, "missing request headers")
      return true
    end)
    .is_truthy("failed to await successful response for " .. msg)

  local value = headers[header_name]
  assert.not_equals(header_value, value, msg)
end


local function assert_ee_plugin_ok(node_1_client, node_2_client, msg)
  check_ee_plugin(node_1_client, "node_1: " .. msg)
  check_ee_plugin(node_2_client, "node_2: " .. msg)
end

local function recover_keyring(client, private_key)
    local res = client:post("/keyring/recover",
                            json({ recovery_private_key = private_key }))
    assert.res_status(200, res)
    res = assert.response(res).has.jsonbody()
    assert.same("successfully recovered 1 keys", res.message)
end

local function setup_distribution()
  local kld = os.getenv("KONG_LICENSE_DATA")
  helpers.unsetenv("KONG_LICENSE_DATA")

  local klp = os.getenv("KONG_LICENSE_PATH")
  helpers.unsetenv("KONG_LICENSE_PATH")

  local tmp_filename = "/tmp/distributions_constants.lua"
  assert(helpers.file.copy("kong/enterprise_edition/distributions_constants.lua",
                           tmp_filename, true))
  assert(helpers.file.copy("spec-ee/fixtures/mock_distributions_constants.lua",
                           "kong/enterprise_edition/distributions_constants.lua", true))

  return function()
    if kld then
      helpers.setenv("KONG_LICENSE_DATA", kld)
    end

    if klp then
      helpers.setenv("KONG_LICENSE_PATH", klp)
    end

    if helpers.path.exists(tmp_filename) then
      -- restore and delete backup
      assert(helpers.file.copy(tmp_filename,
                               "kong/enterprise_edition/distributions_constants.lua", true))
      assert(helpers.file.delete(tmp_filename))
    end
  end
end

local function assert_get_licenses(client, license_id, msg)
  -- get by collection
  local res = client:get("/licenses")
  assert.res_status(200, res)
  res = assert.response(res).has.jsonbody()
  assert.is_table(res.data, msg)
  assert.equals(1, #res.data, msg)
  assert.equals(license_id, assert.is_string(res.data[1].id), msg)

  -- get by id
  assert.res_status(200, client:get("/licenses/" .. license_id), msg)
end

local function assert_no_license_entities(client, msg)
  local res = client:get("/licenses")
  assert.res_status(200, res)
  res = assert.response(res).has.jsonbody()
  assert.is_table(res.data, "invalid response from `GET /licenses`: " .. msg)
  assert.same({}, res.data, "expected no license entities: " .. msg)
end

local function assert_encrypted_db_license_warning(prefix)
  assert.logfile(prefix .. "/logs/error.log")
    .has.line("found one or more keyring-encrypted licenses in the database", true)
end

local function new_conf(extra)
  local conf = {
    db_update_frequency = 1,
    keyring_enabled = "on",
    keyring_strategy = "cluster",
    nginx_conf = "spec/fixtures/custom_nginx.template",
    plugins = "request-transformer-advanced",
    worker_state_update_frequency = 1,
  }

  for k, v in pairs(extra or {}) do
    conf[k] = v
  end

  return conf
end

local function new_hybrid_conf(extra)
  local conf = new_conf({
    cluster_cert = "spec/fixtures/kong_clustering.crt",
    cluster_cert_key = "spec/fixtures/kong_clustering.key",
  })

  for k, v in pairs(extra or {}) do
    conf[k] = v
  end

  return conf
end

describe("Keyring license encryption #postgres", function()
  local reset_distribution
  local license, license_key, private_key

  lazy_setup(function()
    license = assert(helpers.file.read("spec-ee/fixtures/mock_license.json"))
    license_key = assert(cjson.decode(license).license.payload.license_key)
    private_key = assert(helpers.file.read("spec-ee/fixtures/keyring/key.pem"))
  end)

  describe("#traditional", function()
    local node_1_admin, node_2_admin
    local node_1_proxy, node_2_proxy

    local node_1 = new_conf({
      prefix = "node_1",
      database = "postgres",
      keyring_recovery_public_key = "spec-ee/fixtures/keyring/pub.pem",
    })

    local node_2 = new_conf({
      prefix = "node_2",
      database = "postgres",
      proxy_listen = "127.0.0.1:9200",
      admin_listen = "127.0.0.1:9201",
    })

    local node_1_errlog = node_1.prefix .. "/logs/error.log"
    local node_2_errlog = node_2.prefix .. "/logs/error.log"

    local db

    lazy_setup(function()
      reset_distribution = setup_distribution()

      -- run migrations, reset tables
      local bp
      bp, db = helpers.get_db_utils("postgres", {
        "routes",
        "services",
        "plugins",
        "keyring_meta",
        "keyring_keys",
        "licenses",
      } )

      local service = assert(bp.services:insert({
        path = "/request",
      }))
      assert(bp.routes:insert({
        paths = { "/test" },
        service = service,
      }))

      assert(bp.plugins:insert({
        name = "request-transformer-advanced",
        config = {
          add = {
            headers = {
              "x-test:123",
            },
          },
        },
      }))

      assert(helpers.start_kong(node_1))
      assert(helpers.start_kong(node_2))

      node_1_proxy = helpers.proxy_client()
      node_2_proxy = helpers.proxy_client(nil, 9200)
      -- reopen proxy client connections after restart
      node_1_proxy.reopen = true
      node_2_proxy.reopen = true

      node_1_admin = helpers.admin_client()
      node_2_admin = helpers.admin_client(9201)
    end)

    lazy_teardown(function()
      if node_1_proxy then
        node_1_proxy:close()
      end

      if node_2_proxy then
        node_2_proxy:close()
      end

      if node_1_admin then
        node_1_admin:close()
      end

      if node_2_admin then
        node_2_admin:close()
      end

      helpers.stop_kong(node_1.prefix)
      helpers.stop_kong(node_2.prefix)

      assert(db:truncate())

      reset_distribution()
    end)

    it("recovery", function()
      local res

      -- initial state
      await_license(node_1_admin, UNLICENSED,
                    "node_1: expected no active license at startup")
      await_license(node_2_admin, UNLICENSED,
                    "node_2: expected no active license at startup")

      -- sanity check: ensure there's nothing in the DB yet
      assert_no_license_entities(node_1_admin, "node_1: before adding a license")
      assert_no_license_entities(node_2_admin, "node_2: before addint a license")

      -- add a new license
      res = node_1_admin:post("/licenses", json({ payload = license }))
      res = assert.response(res).has.jsonbody()
      local license_id = assert.is_string(res.id)

      -- license added
      await_license(node_1_admin, license_key,
                    "node_1: expected active license after adding one")
      await_license(node_2_admin, license_key,
                    "node_2: expected active license after adding one")

      -- sanity check: GET /licenses returns what we expect
      assert_get_licenses(node_1_admin, license_id, "node_1: after adding license")
      assert_get_licenses(node_2_admin, license_id, "node_2: after adding license")

      -- sanity check: proxying is alive and well
      assert_ee_plugin_ok(node_1_proxy, node_2_proxy, "after adding a license")

      -- stop node_2 first so that it cannot be used to recover node_1's keyring
      assert(helpers.stop_kong(node_2.prefix, true))
      helpers.clean_logfile(node_1_errlog)
      assert(helpers.restart_kong(node_1))

      -- the license still exists in the DB but is unreadable due to encryption
      await_license(node_1_admin, UNLICENSED,
                    "node_1: expected no active license after restart before keyring recovery")

      assert_encrypted_db_license_warning(node_1.prefix)

      -- node_1 is unlicensed, so the request-transformer-advanced plugin
      -- should not execute
      check_ee_plugin_neg(node_1_proxy, "node_1: after restart, before keyring recovery")

      -- execute keyring recovery
      recover_keyring(node_1_admin, private_key)

      -- license activated
      await_license(node_1_admin, license_key,
                    "node_1: license should be activated after keyring recovery")

      -- start node_2 and await cluster keyring recovery
      helpers.clean_logfile(node_2_errlog)
      assert(helpers.start_kong(node_2, nil, true))

      assert_encrypted_db_license_warning(node_2.prefix)

      await_license(node_2_admin, license_key,
                    "node_2: license should be reactivated after keyring cluster initialization")
      assert.logfile(node_2_errlog).has.line("loaded license from database", true, 5)

      -- sanity check: the license is readable via the DB/admin api
      assert_get_licenses(node_1_admin, license_id, "node_1: after license reactivation")
      assert_get_licenses(node_2_admin, license_id, "node_2: after license reactivation")

      -- sanity check: proxying is alive and well
      assert_ee_plugin_ok(node_1_proxy, node_2_proxy, "after after keyring recovery")
    end)
  end)

  describe("#hybrid", function()
    local cp_1_admin, cp_2_admin
    local dp_1_proxy, dp_2_proxy

    local cp_1 = new_hybrid_conf({
      prefix = "cp_1",
      role = "control_plane",
      database = "postgres",
      keyring_recovery_public_key = "spec-ee/fixtures/keyring/pub.pem",
      admin_listen = "127.0.0.1:9001",
      cluster_listen = "127.0.0.1:9005",
      cluster_telemetry_listen = "127.0.0.1:9006",
    })

    local cp_2 = new_hybrid_conf({
      prefix = "cp_2",
      role = "control_plane",
      database = "postgres",
      admin_listen = "127.0.0.1:9201",
      cluster_listen = "127.0.0.1:9205",
      cluster_telemetry_listen = "127.0.0.1:9206",
    })

    local dp_1 = new_hybrid_conf({
      prefix = "dp_1",
      database = "off",
      role = "data_plane",
      proxy_listen = "127.0.0.1:9000",
      cluster_control_plane = cp_1.cluster_listen,
      cluster_telemetry_endpoint = "127.0.0.1:9006",
    })

    local dp_2 = new_hybrid_conf({
      prefix = "dp_2",
      database = "off",
      role = "data_plane",
      proxy_listen = "127.0.0.1:9200",
      cluster_control_plane = cp_2.cluster_listen,
      cluster_telemetry_endpoint = "127.0.0.1:9006",
    })

    local db
    local plugin

    lazy_setup(function()
      reset_distribution = setup_distribution()

      -- run migrations, reset tables
      local bp
      bp, db = helpers.get_db_utils("postgres", {
        "routes",
        "services",
        "plugins",
        "keyring_meta",
        "keyring_keys",
        "licenses",
      } )

      local service = assert(bp.services:insert({
        path = "/request",
      }))
      assert(bp.routes:insert({
        paths = { "/test" },
        service = service,
      }))

      plugin = assert(bp.plugins:insert({
        name = "request-transformer-advanced",
        config = {
          add = {
            headers = {
              "X-Test:123",
            },
          },
        },
      }))

      assert(helpers.start_kong(cp_1))
      assert(helpers.start_kong(cp_2))

      cp_1_admin = helpers.admin_client()
      cp_2_admin = helpers.admin_client(9201)

      assert(helpers.start_kong(dp_1))
      dp_1_proxy = helpers.proxy_client()
      -- reopen proxy client connections after restart
      dp_1_proxy.reopen = true

      assert(helpers.start_kong(dp_2))
      dp_2_proxy = helpers.proxy_client(9200)
      -- reopen proxy client connections after restart
      dp_2_proxy.reopen = true
    end)

    lazy_teardown(function()
      if dp_1_proxy then
        dp_1_proxy:close()
      end

      if dp_2_proxy then
        dp_2_proxy:close()
      end

      if cp_1_admin then
        cp_1_admin:close()
      end

      if cp_2_admin then
        cp_2_admin:close()
      end

      helpers.stop_kong(cp_1.prefix)
      helpers.stop_kong(cp_2.prefix)
      helpers.stop_kong(dp_1.prefix)
      helpers.stop_kong(dp_2.prefix)

      assert(db:truncate())

      reset_distribution()
    end)

    it("recovery", function()
      local res

      -- initial state
      await_license(cp_1_admin, UNLICENSED,
                    "cp_1: expected no active license at startup")
      await_license(cp_2_admin, UNLICENSED,
                    "cp_2: expected no active license at startup")

      -- add a new license
      res = cp_1_admin:post("/licenses", json({ payload = license }))
      res = assert.response(res).has.jsonbody()
      local license_id = assert.is_string(res.id)

      -- license added
      await_license(cp_1_admin, license_key,
                    "cp_1: expected active license after adding one")
      await_license(cp_2_admin, license_key,
                    "cp_2: expected active license after adding one")

      -- sanity check: GET /licenses returns what we expect
      assert_get_licenses(cp_1_admin, license_id, "cp_1: after adding license")
      assert_get_licenses(cp_2_admin, license_id, "cp_2: after adding license")

      -- sanity check: proxying is alive and well
      check_ee_plugin(dp_1_proxy, "dp: after adding a license")

      -- stop the DPs so that they not receive our next config change
      assert(helpers.stop_kong(dp_1.prefix, true))
      assert(helpers.stop_kong(dp_2.prefix, true))

      local new_header = "x-test-new"
      local new_header_value = "456"

      -- update the plugin config
      res = cp_1_admin:patch("/plugins/" .. plugin.id, json({
        config = {
          add = {
            headers = {
              "x-test:123",
              new_header .. ":" .. new_header_value,
            },
          },
        },
      }))
      assert.res_status(200, res)

      -- stop cp_2 first so that it cannot be used to recover cp_1's keyring
      assert(helpers.stop_kong(cp_2.prefix, true))
      assert(helpers.restart_kong(cp_1))

      -- the license still exists in the DB but is unreadable due to encryption
      assert_encrypted_db_license_warning(cp_1.prefix)
      await_license(cp_1_admin, UNLICENSED,
                    "cp_1: expected no active license after restart before keyring recovery")

      assert(helpers.start_kong(dp_1, nil, true))
      check_ee_plugin(dp_1_proxy, "dp_1 should start up and handle proxy requests "
                               .. "before keyring recovery")

      check_ee_plugin_neg(dp_1_proxy,
                          "dp_1 should not have an updated config before keyring recovery",
                          new_header, new_header_value)

      assert(helpers.start_kong(dp_2, nil, true))
      check_ee_plugin(dp_2_proxy, "dp_2 should start up and handle proxy requests "
                               .. "before keyring recovery")

      check_ee_plugin_neg(dp_2_proxy,
                          "dp_2 should not have an updated config before keyring recovery",
                          new_header, new_header_value)

      -- execute keyring recovery
      recover_keyring(cp_1_admin, private_key)

      -- license activated
      await_license(cp_1_admin, license_key,
                    "cp_1: license should be activated after keyring recovery")

      -- sanity check: proxying is alive and well
      check_ee_plugin(dp_1_proxy, "dp_1: after keyring recovery")
      -- sanity check: dp received our updated plugin config
      check_ee_plugin(dp_1_proxy, "dp_1: after keyring recovery",
                      new_header, new_header_value)

      -- start cp_2 and await cluster keyring recovery
      helpers.clean_logfile(cp_2.prefix .. "/logs/error.log")
      assert(helpers.start_kong(cp_2, nil, true))
      assert_encrypted_db_license_warning(cp_2.prefix)
      await_license(cp_2_admin, license_key,
                    "cp_2: license should be reactivated after keyring cluster initialization")

      -- sanity check: the license is readable via the DB/admin api
      assert_get_licenses(cp_1_admin, license_id, "cp_1: after license reactivation")
      assert_get_licenses(cp_2_admin, license_id, "cp_2: after license reactivation")

      -- sanity check: proxying is alive and well
      check_ee_plugin(dp_2_proxy, "dp_2: after keyring recovery")
      -- sanity check: dp received our updated plugin config
      check_ee_plugin(dp_2_proxy, "dp_2: after keyring recovery",
                      new_header, new_header_value)
    end)
  end)
end)
