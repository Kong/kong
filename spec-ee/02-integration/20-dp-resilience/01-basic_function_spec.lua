-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson_decode = require("cjson").decode
local KONG_VERSION = require("kong.meta").version


local http_mock = {
  validation_config = [[
    server {
        listen 12345;

        location "/" {
          content_by_lua_block {
            ngx.status = 200
            ngx.print("ok")
          }
        }
      }
  ]]
}

local test_config = [[
{
  "_format_version": "3.0",
  "services": [
    {
      "name": "test",
      "host": "localhost",
      "path": "/",
      "port": 12345,
      "routes": [
        {
          "name": "test",
          "paths": [ "/" ]
        }
      ]
    }
  ]
}
]]

local S3PORT = 4566

local function configure(client)
  local res = assert(client:send {
    method = "POST",
    path = "/services",
    body = {
      name = "test",
      url = "http://example.com/test",
    },
    headers = {
      ["Content-Type"] = "application/json",
    }
  })
  assert.response(res).has.status(201)
  res = assert(client:send {
    method = "POST",
    path = "/services/test/routes",
    body = {
      name = "test",
      paths = { "/", },
    },
    headers = {
      ["Content-Type"] = "application/json",
    }
  })
  assert.response(res).has.status(201)
end

local function verify_body(body)
  local decoded = cjson_decode(body)
  assert(decoded.routes)
  assert(decoded.routes[1])
  assert.same("test", decoded.services[1].name)
  assert.same("example.com", decoded.services[1].host)
  assert.same("/test", decoded.services[1].path)
  assert.same("test", decoded.routes[1].name)
  assert.same({"/"}, decoded.routes[1].paths)
end

local function verify_aws_request(headers)
  assert(headers.Authorization:match(
    [[AWS4%-HMAC%-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/%d+/us%-east%-1/s3/aws4_request, SignedHeaders=[%-%w,;]+, Signature=%w+]]),
    headers.Authorization)
  assert(headers["X-Amz-Date"])
  assert(headers["X-Amz-Content-Sha256"])
  assert.same("127.0.0.1:4566", headers.Host)
end

for _, strategy in helpers.all_strategies() do
describe("cp outage handling", function ()
  local mock_server
  local cluster_fallback_config_storage = "s3://test_bucket/test_prefix"
  lazy_setup(function()
    helpers.setenv("AWS_REGION", "us-east-1")
    helpers.setenv("AWS_DEFAULT_REGION", "us-east-1")
    helpers.setenv("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
    helpers.setenv("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    helpers.setenv("AWS_CONFIG_STORAGE_ENDPOINT", "http://127.0.0.1:" .. S3PORT)

    mock_server = helpers.http_mock(S3PORT, {
      timeout = 10,
    })
  end)

  lazy_teardown(function()
    assert(mock_server("closing", true))
  end)

  for _, exporter_role in ipairs{"CP", "DP"} do
    describe("upload from " .. exporter_role, function()
      local client

      before_each(function()
        -- clean up database
        helpers.get_db_utils(strategy, {
          "services",
          "routes",
        })

        -- start cp&dp
        assert(helpers.start_kong({
          role = "control_plane",
          database = strategy,
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
          cluster_fallback_config_storage = exporter_role == "CP" and  cluster_fallback_config_storage or nil,
          cluster_fallback_config_export = exporter_role == "CP" and "on" or "off",
          cluster_fallback_config_export_delay = 2,
          db_update_frequency = 0.1,
          cluster_listen = "127.0.0.1:9005",
        }))
        assert(helpers.start_kong({
          role = "data_plane",
          database = "off",
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
          cluster_fallback_config_storage = exporter_role == "DP" and  cluster_fallback_config_storage or nil,
          cluster_fallback_config_export = exporter_role == "DP" and "on" or "off",
          cluster_fallback_config_export_delay = 2,
          cluster_control_plane = "127.0.0.1:9005",
          proxy_listen = "127.0.0.1:9006", -- otherwise it won't start
          stream_listen = "off",
        }))
        client = helpers.admin_client()
      end)
    
      after_each(function ()
        helpers.stop_kong("servroot2")
        helpers.stop_kong()
      end)

      it("test #flaky", function()
        configure(client)

        local ok, err
        -- try at most 2 times. 
        -- the first time we expect to get an empty config
        -- as the CP is sending out its first config when starting up
        for _ = 1, 2 do
          ok, err = pcall(function()
            local lines, body, headers = mock_server()
            assert(lines, body)
            assert.same("PUT /test_bucket/test_prefix/" .. KONG_VERSION .. "/config.json? HTTP/1.1", lines[1])
            verify_aws_request(headers)
            verify_body(body)
          end)
          if ok then break end
        end
        assert(ok, err)
      end)
    end)
  end

  describe("download", function()
    before_each(function()
      -- start dp
      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot3",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_fallback_config_storage = cluster_fallback_config_storage,
        cluster_fallback_config_import = "on",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9003",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, {
        http_mock = http_mock
      }))
    end)


    after_each(function ()
      helpers.stop_kong("servroot3")
    end)


    it("test #flaky", function()
      local lines, body, headers = mock_server("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n".. test_config)
      assert(lines, body)
      verify_aws_request(headers)
      assert.same("GET /test_bucket/test_prefix/" .. KONG_VERSION .. "/config.json? HTTP/1.1", lines[1])
      assert.Nil(body)

      -- test if it takes effect
      local pclient = helpers.proxy_client(nil, 9003)

      helpers.pwait_until(function ()
        assert.logfile("servroot3/logs/error.log").has.line("fallback config applied")
        assert.res_status(200, assert(pclient:send {
          method = "GET",
          path = "/"
        }))
      end, 10)
    end)
  end)
end)
end
