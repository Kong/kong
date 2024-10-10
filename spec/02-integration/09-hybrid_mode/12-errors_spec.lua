local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local uuid = require "kong.tools.uuid"
local constants = require "kong.constants"
local mock_cp = require "spec.fixtures.mock_cp"

local CONFIG_PARSE = constants.CLUSTERING_DATA_PLANE_ERROR.CONFIG_PARSE
local RELOAD = constants.CLUSTERING_DATA_PLANE_ERROR.RELOAD

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
local function get_error_report(client, msg)
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


-- XXX TODO: mock_cp does not support incremental sync rpc
for _, inc_sync in ipairs { "off"  } do
for _, strategy in helpers.each_strategy() do
  describe("CP/DP sync error-reporting with #" .. strategy .. " inc_sync=" .. inc_sync .. " backend", function()
    local client
    local cluster_port
    local cluster_ssl_port
    local fixtures
    local exception_fname = helpers.test_conf.prefix .. "/throw-an-exception"

    lazy_setup(function()
      cluster_port = helpers.get_available_port()
      cluster_ssl_port = helpers.get_available_port()

      fixtures = {
        http_mock = {
          control_plane = mock_cp.fixture(cluster_port, cluster_ssl_port)
        },
      }

      helpers.clean_prefix()

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
        plugins                     = "bundled,cluster-error-reporting",
        cluster_incremental_sync = inc_sync,
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      os.remove(exception_fname)
      client = helpers.http_client("127.0.0.1", cluster_port)
      client.reopen = true
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    it("reports invalid configuration errors", function()
      set_cp_payload(client, {
        type = "reconfigure",
        config_table = {
          _format_version = "3.0",
          extra_top_level_field = "I don't belong here",
          services = {
            {
              id = uuid.uuid(),
              name = "my-service",
              extra_field = 123,
              tags = { "tag-1", "tag-2" },
            },
          },
        }
      })

      local e = get_error_report(
        client,
        "the data-plane should return an  'invalid declarative configuration' "
        .. "error to the control-plane after sending it an invalid config"
      )

      assert.equals(CONFIG_PARSE, e.error.name)

      assert.is_string(e.error.config_hash, "payload is missing 'config_hash'")
      assert.is_string(e.error.message, "payload is missing 'message'")
      assert.is_string(e.error.source, "payload is missing 'source'")

      assert.is_table(e.error.fields, "payload is missing 'fields'")
      assert.not_nil(e.error.fields.extra_top_level_field,
                     "expected error message for 'extra_top_level_field'")

      assert.is_table(e.error.flattened_errors, "payload is missing 'flattened_errors'")
      assert.equals(1, #e.error.flattened_errors, "expected 1 flattened entity error")

      local entity_err = e.error.flattened_errors[1]
      assert.is_table(entity_err, "invalid entity error in 'flattened_errors'")
      assert.equals("service", entity_err.entity_type)
      assert.equals("my-service", entity_err.entity_name)
      assert.is_table(entity_err.entity_tags)
      assert.is_table(entity_err.errors)
      assert.equals(2, #entity_err.errors, "expected 2 errors for 'my-service' entity")

      assert.is_nil(entity_err.entity, "entity should be removed from errors "
                                    .. "within 'flattened_errors'")
    end)

    it("reports exceptions encountered during config reload", function()
      helpers.file.write(exception_fname, "boom!")

      set_cp_payload(client, {
        type = "reconfigure",
        config_table = {
          _format_version = "3.0",
          services = {
            {
              id = uuid.uuid(),
              name = "my-service",
              url = "http://127.0.0.1:80/",
              tags = { "tag-1", "tag-2" },
            },
          },
        }
      })

      assert.logfile().has.line("throwing an exception", true, 10)

      local e = get_error_report(
        client,
        "the data-plane should report exceptions encountered during config reload"
      )

      assert.is_string(e.error.config_hash, "payload is missing 'config_hash'")
      assert.is_string(e.error.message, "payload is missing 'message'")
      assert.is_string(e.error.source, "payload is missing 'source'")

      assert.equals(RELOAD, e.error.name)
      assert.is_string(e.error.exception, "payload is missing 'exception'")
      assert.matches("boom!", e.error.exception)
      assert.is_string(e.error.traceback, "payload is missing 'traceback'")
    end)

    it("reports other types of errors", function()
      local services = {}

      -- The easiest way to test for this class of error is to generate a
      -- config payload that is too large to fit in the configured
      -- `lmdb_map_size`, so this test works by setting a low limit of 1MB on
      -- the data plane and then attempting to generate a config payload that
      -- is 2MB in hopes that it will be too large for the data plane.
      local size = 1024 * 1024 * 2

      while #cjson.encode(services) < size do
        for i = #services, #services + 1000 do
          i = i + 1

          services[i] = {
            id = uuid.uuid(),
            name = "service-" .. i,
            host = "127.0.0.1",
            retries = 5,
            protocol = "http",
            port = 80,
            path = "/",
            connect_timeout = 1000,
            write_timeout = 1000,
            tags = {
              "tag-1", "tag-2", "tag-3",
            },
            enabled = true,
          }
        end
      end

      set_cp_payload(client, {
        type = "reconfigure",
        config_table = {
          _format_version = "3.0",
          services = services,
        }
      })

      local e = get_error_report(
        client,
        "the data-plane should return a 'map full' error after sending it a"
        .. " config payload of >2MB"
      )

      assert.is_string(e.error.config_hash, "payload is missing 'config_hash'")
      assert.is_string(e.error.message, "payload is missing 'message'")
      assert.is_string(e.error.source, "payload is missing 'source'")

      assert.equals(RELOAD, e.error.name)
      assert.equals("map full", e.error.message)
    end)
  end)
end -- for _, strategy
end -- for inc_sync
