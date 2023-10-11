-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_file   = require "pl.file"
local cjson = require "cjson.safe"
local clear_license_env = require("spec-ee.02-integration.04-dev-portal.utils").clear_license_env

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
  local reset_license_data

  lazy_setup(function()
    local _, db = helpers.get_db_utils(nil, {})

    assert(db.licenses:truncate())
    helpers.clean_logfile("servroot-cp/logs/error.log")
    helpers.clean_logfile("servroot-dp/logs/error.log")
    reset_license_data = clear_license_env()

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
      portal_gui_listen     = "off",
      portal_api_listen     = "off",
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
  end)

  lazy_teardown(function()
    helpers.stop_kong("servroot-cp")
    helpers.stop_kong("servroot-dp")
    reset_license_data()
  end)

  it("should be failed with fips-on", function()
    assert.logfile("servroot-cp/logs/error.log").has.line("Kong is started without a valid license while FIPS mode")
    assert.logfile("servroot-dp/logs/error.log").has.line("Kong is started without a valid license while FIPS mode")
    assert.logfile("servroot-cp/logs/error.log").has.no.line("enabling FIPS mode on OpenSSL")
    assert.logfile("servroot-dp/logs/error.log").has.no.line("enabling FIPS mode on OpenSSL")

    helpers.clean_logfile("servroot-cp/logs/error.log")
    helpers.clean_logfile("servroot-dp/logs/error.log")

    local admin_client = assert(helpers.http_client("127.0.0.1", 9001))
    local res, _ = admin_client:send({
      method = "POST",
      path = "/licenses/",
      body = cjson.encode({ payload = pl_file.read("spec-ee/fixtures/mock_license.json") }),
      headers = {
        ["Content-Type"] = "application/json",
      },
    })
    assert.res_status(201, res)
    assert(admin_client:close())

    helpers.wait_until(function()
      return find_in_file("servroot-cp/logs/error.log", "enabling FIPS mode on OpenSSL") and
             find_in_file("servroot-dp/logs/error.log", "enabling FIPS mode on OpenSSL") and
             not find_in_file("servroot-cp/logs/error.log", "FIPS mode is not supported in Free mode") and
             not find_in_file("servroot-dp/logs/error.log", "FIPS mode is not supported in Free mode")
    end, 10)
  end)
end)
