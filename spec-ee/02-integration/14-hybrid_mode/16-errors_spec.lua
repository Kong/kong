-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local constants = require "kong.constants"
local mock_cp = require "spec.fixtures.mock_cp"
local pl_file = require "pl.file"
local http_mock = require "spec.helpers.http_mock"
local utils = require "kong.tools.utils"

local CONFIG_PARSE = constants.CLUSTERING_DATA_PLANE_ERROR.CONFIG_PARSE
local STATE_UPDATE_FREQUENCY = .2

local function json(data)
  return {
    headers = {
      ["accept"] = "application/json",
      ["content-type"] = "application/json",
    },
    body = assert(cjson.encode(data)),
  }
end


local function set_cp_payload(client, payload)
  local res = client:post("/payload", json(payload))
  assert.response(res).has.status(201)
end


local function get_connection_log(client)
  local res = client:get("/log")
  assert.response(res).has.status(200)
  local body = assert.response(res).has.jsonbody()
  assert.is_table(body.data)

  return body.data
end


---@param client table
---@param msg string
---@return { error: kong.clustering.config_helper.update.err_t }
local function get_error_report_or_fail(client, msg)
  local err_t

  assert.eventually(function()
    local entries = get_connection_log(client)

    if #entries == 0 then
      return nil, { err = "no data plane client log entries" }
    end

    for _, entry in ipairs(entries) do
      if    entry.event == "client-recv"
        and entry.type  == "binary"
        and type(entry.json) == "table"
        and entry.json.type == "error"
        then
          err_t = entry.json
          return true
        end
      end

      return nil, {
        err = "did not find expected error in log",
        entries = entries,
      }
  end)
  .is_truthy(msg)

  return err_t
end


for _, strategy in helpers.each_strategy() do
  describe("CP/DP sync error-reporting with #" .. strategy .. " backend", function()
    local client
    local cluster_port
    local cluster_ssl_port
    local fixtures
    local proxy_client
    local proxy_port
    local proxy_server
    local fname = helpers.test_conf.prefix .. "/license-error-validation"

    lazy_setup(function()
      cluster_port = helpers.get_available_port()
      cluster_ssl_port = helpers.get_available_port()
      proxy_port = helpers.get_available_port()
      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      helpers.unsetenv("KONG_LICENSE_PATH")
      helpers.unsetenv("KONG_TEST_LICENSE_PATH")

      fixtures = {
        http_mock = {
          control_plane = mock_cp.fixture(cluster_port, cluster_ssl_port)
        },
      }

      proxy_server = http_mock.new(proxy_port)
      proxy_server:start()

      assert(helpers.start_kong({
        role                        = "data_plane",
        database                    = "off",
        nginx_conf                  = "spec/fixtures/custom_nginx.template",
        cluster_cert                = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key            = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane       = "127.0.0.1:" .. tostring(cluster_ssl_port),
        -- use a small map size so that it's easy for us to max it out
        lmdb_map_size               = "1m",
        plugins                     = "bundled,cluster-error-reporting,license-error-validation,reconfiguration-completion",
        worker_consistency          = "eventual",
        worker_state_update_frequency = STATE_UPDATE_FREQUENCY,
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      proxy_server:stop()
    end)

    before_each(function()
      client = helpers.http_client("127.0.0.1", cluster_port)
      client.reopen = true
      pl_file.delete(fname)
      proxy_client = assert(helpers.proxy_client())
    end)

    after_each(function()
      if client then
        client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
      pl_file.delete(fname)
    end)

    it("reports invalid JSON license error", function()
      local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
      local d = f:read("*a")
      f:close()

      helpers.file.write(fname, "ERROR_INVALID_LICENSE_JSON")

      set_cp_payload(client, {
        type = "reconfigure",
        config_table = {
          _format_version = "3.0",
          routes = {
            {
              paths = { "/A" },
            },
          },
          licenses = {
            {
              payload = d,
            }
          }
        }
      })

      local e = get_error_report_or_fail(
        client,
        "the data-plane should return an  'invalid declarative configuration' "
        .. "error to the control-plane after sending it an invalid config"
      )

      assert.equals(CONFIG_PARSE, e.error.name)

      assert.equals(1, #e.error.flattened_errors, "expected 1 flattened entity error")

      local entity_err = e.error.flattened_errors[1]
      assert.is_table(entity_err, "invalid entity error in 'flattened_errors'")
      assert.equals("license", entity_err.entity_type)
      assert.is_table(entity_err.errors)
      assert.equals(1, #entity_err.errors, "expected 1 error for 'license' entity")

      local error = entity_err.errors[1]
      assert.equals("Unable to validate license: could not decode license json", error.message)
    end)

    it("reports invalid license format error", function()
      local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
      local d = f:read("*a")
      f:close()

      helpers.file.write(fname, "ERROR_INVALID_LICENSE_FORMAT")

      set_cp_payload(client, {
        type = "reconfigure",
        config_table = {
          _format_version = "3.0",
          routes = {
            {
              paths = { "/A" },
            },
          },
          licenses = {
            {
              payload = d,
            }
          }
        }
      })

      local e = get_error_report_or_fail(
        client,
        "the data-plane should return an  'invalid declarative configuration' "
        .. "error to the control-plane after sending it an invalid config"
      )

      assert.equals(CONFIG_PARSE, e.error.name)

      assert.equals(1, #e.error.flattened_errors, "expected 1 flattened entity error")

      local entity_err = e.error.flattened_errors[1]
      assert.is_table(entity_err, "invalid entity error in 'flattened_errors'")
      assert.equals("license", entity_err.entity_type)
      assert.is_table(entity_err.errors)
      assert.equals(1, #entity_err.errors, "expected 1 error for 'license' entity")

      local error = entity_err.errors[1]
      assert.equals("Unable to validate license: invalid license format", error.message)
    end)

    it("does NOT report expired license error", function()
      local f = assert(io.open("spec-ee/fixtures/expired_license.json"))
      local d = f:read("*a")
      f:close()

      helpers.file.write(fname, "ERROR_LICENSE_EXPIRED")

      local configuration_version = utils.uuid()

      set_cp_payload(client, {
        type = "reconfigure",
        config_table = {
          _format_version = "3.0",
          services = {
            {
              host = "localhost",
              port = proxy_port,
              id = "01a2b3c4-d5e6-f7a8-b9c0-d1e2f3a4b5c7"
            },
          },
          routes = {
            {
              paths = { "/" },
              service = { id = "01a2b3c4-d5e6-f7a8-b9c0-d1e2f3a4b5c7" }
            },
          },
          plugins = {
            {
              name = "reconfiguration-completion",
              config = {
                version = configuration_version,
              }
            }
          },
          licenses = {
            {
              payload = d,
            }
          },
        }
      })

      assert.eventually(function()
        local res = proxy_client:get("/", {
          headers = {
            ["If-Kong-Configuration-Version"] = configuration_version
          }
        })
        local body = assert.res_status(200, res)
        assert.equals("ok", body)
        assert.equals("complete", res.headers["X-Kong-Reconfiguration-Status"])
      end)
      .with_timeout(30)
      .has_no_error()
    end)
  end)
end
