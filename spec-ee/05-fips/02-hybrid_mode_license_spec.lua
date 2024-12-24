-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local clear_license_env = require("spec-ee.helpers").clear_license_env
local setup_distribution = require("spec-ee.helpers").setup_distribution

local function find_in_file(filepath, pat)
  local f = assert(io.open(filepath, "r"))

  local line = f:read("*l")

  local found = false
  while line and not found do
    if line:find(pat, 1, true) then
      found = true
    end

    line = f:read("*l")
  end

  f:close()

  return found
end

describe("CP/DP FIPS avaiability test", function()
  local reset_license_data, reset_distribution
  local admin_client

  local _, db = helpers.get_db_utils(nil)

  before_each(function()
    db.licenses:truncate()
    helpers.clean_logfile("servroot-cp/logs/error.log")
    helpers.clean_logfile("servroot-dp/logs/error.log")
    reset_license_data = clear_license_env()
    reset_distribution = setup_distribution()

    assert(helpers.start_kong({
      prefix = "servroot-cp",
      fips = "on",
      role = "control_plane",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      admin_listen = "127.0.0.1:9001",
      admin_gui_listen = "off",
      cluster_listen = "127.0.0.1:9006",
      cluster_telemetry_listen = "127.0.0.1:9008",
      portal_gui_listen = "off",
      portal_api_listen = "off",
    }))

    assert(helpers.start_kong({
      prefix = "servroot-dp",
      fips = "on",
      role = "data_plane",
      database = "off",
      proxy_listen = "127.0.0.1:9000",
      cluster_control_plane = "127.0.0.1:9006",
      cluster_telemetry_endpoint = "127.0.0.1:9008",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
    }))

    admin_client = assert(helpers.http_client("127.0.0.1", 9001))
  end)

  after_each(function()
    admin_client:close()
    helpers.stop_kong("servroot-cp")
    helpers.stop_kong("servroot-dp")
    reset_license_data()
    reset_distribution()
  end)

  it("should be failed with fips-on", function()
    assert.logfile("servroot-cp/logs/error.log").has.line("Kong is started without a valid license while FIPS mode")
    assert.logfile("servroot-dp/logs/error.log").has.line("Kong is started without a valid license while FIPS mode")
    assert.logfile("servroot-cp/logs/error.log").has.no.line("enabling FIPS mode on OpenSSL")
    assert.logfile("servroot-dp/logs/error.log").has.no.line("enabling FIPS mode on OpenSSL")

    helpers.clean_logfile("servroot-cp/logs/error.log")
    helpers.clean_logfile("servroot-dp/logs/error.log")

    local res, err = admin_client:send({
      method = "POST",
      path = "/licenses/",
      body = { payload = pl_file.read("spec-ee/fixtures/mock_license.json") },
      headers = {
        ["Content-Type"] = "application/json",
      },
    })
    assert.is_nil(err)
    assert.res_status(201, res)

    helpers.wait_until(function()
      return find_in_file("servroot-cp/logs/error.log", "enabling FIPS mode on OpenSSL") and
             find_in_file("servroot-dp/logs/error.log", "enabling FIPS mode on OpenSSL")
    end, 10)
  end)

  it("fips enablement status in admin API responding to license conf changes", function()
    local res, err = admin_client:send({
      method = "GET",
      path = "/",
    })
    assert.is_nil(err)
    assert.res_status(200, res)

    local json = assert.response(res).has.jsonbody()
    assert.is_falsy(json.configuration.fips)

    res, err = admin_client:send({
      method = "GET",
      path = "/fips-status",
    })
    assert.is_nil(err)
    assert.res_status(200, res)

    json = assert.response(res).has.jsonbody()
    assert.is_falsy(json.active)

    res, err = admin_client:send({
      method = "POST",
      path = "/licenses/",
      body = { payload = pl_file.read("spec-ee/fixtures/mock_license.json") },
      headers = {
        ["Content-Type"] = "application/json",
      },
    })
    assert.is_nil(err)
    assert.res_status(201, res)

    helpers.pwait_until(function()
      res, err = admin_client:send({
        method = "GET",
        path = "/",
      })
      assert.is_nil(err)
      assert.res_status(200, res)

      json = assert.response(res).has.jsonbody()
      assert.truthy(json.configuration.fips)

      res, err = admin_client:send({
        method = "GET",
        path = "/fips-status",
      })
      assert.is_nil(err)
      assert.res_status(200, res)

      json = assert.response(res).has.jsonbody()
      assert.truthy(json.active)
    end, 10)
  end)
end)
