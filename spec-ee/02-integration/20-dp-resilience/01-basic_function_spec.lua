-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local cjson_decode = require("cjson").decode
local KONG_VERSION = require("kong.meta").version

local UPSTREAM_PORT = helpers.get_available_port()
local S3PORT = helpers.get_available_port()
local DP1PORT = helpers.get_available_port()
local DP2PORT = helpers.get_available_port()

local test_config = [[
{
  "_format_version": "3.0",
  "services": [
    {
      "name": "test",
      "host": "localhost",
      "path": "/",
      "port": ]] .. UPSTREAM_PORT .. [[,
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
  assert.same("127.0.0.1:" .. S3PORT, headers.Host)
end

local function verify_aws_sse_request(header)
  assert.same("aws:kms", header["X-Amz-Server-Side-Encryption"])
  assert.same("arn:aws:kms:eu-west-1:412431539555:key/7f57fdbd-646d-4cc7-ae1c-4f29bd4319fd", header["X-Amz-Server-Side-Encryption-Aws-Kms-Key-Id"])
end

local function get_config_uploaded(mock_s3, expected_counts, sse)
  local ret = {}
  local logs = mock_s3:get_all_logs(20)

  local counts = 0
  for _, log in ipairs(logs) do
    local req = assert(log.req)
    verify_aws_request(req.headers)
    if sse and req.method == "PUT" then
      if not pcall(verify_aws_sse_request, req.headers) then
        error(require"inspect"(req))
      end
    end
    -- there will be an empty config at first
    if req.uri:match("/test_bucket/test_prefix/[%d%.]+/config.json") and req.method == "PUT" then
      counts = counts + 1
      ret[#ret + 1] = req.body
    end
  end

  if expected_counts then
    assert.same(expected_counts, counts)
  end

  return ret
end

local function wait_for_final_config(mock_s3, sse)
  helpers.wait_until(function ()
    local ok, config = pcall(get_config_uploaded, mock_s3, nil, sse)
    if not ok then
      return false, config
    end
    local err
    local count = 0
    for _, c in ipairs(config) do
      ok, err = pcall(verify_body, c)
      if ok then
        count = count + 1
      end
    end

    if count == 0 then
      -- return the last error if all configs not what we expected to see
      return false, err or "no config uploaded"
    else
      -- the right config should only be uploaded once
      -- as we have only 1 leader
      assert.same(1, count)
      return true
    end
  end)
end

for _, strategy in helpers.each_strategy() do
describe("cp outage handling", function ()
  local mock_upstream, mock_s3
  local cluster_fallback_config_storage = "s3://test_bucket/test_prefix"
  local cluster_fallback_export_s3_config = [[{"ServerSideEncryption":"aws:kms","SSEKMSKeyId":"arn:aws:kms:eu-west-1:412431539555:key/7f57fdbd-646d-4cc7-ae1c-4f29bd4319fd"}]]
  lazy_setup(function()
    helpers.setenv("AWS_REGION", "us-east-1")
    helpers.setenv("AWS_DEFAULT_REGION", "us-east-1")
    helpers.setenv("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
    helpers.setenv("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    helpers.setenv("AWS_CONFIG_STORAGE_ENDPOINT", "http://127.0.0.1:" .. S3PORT)

    mock_upstream = http_mock.new(UPSTREAM_PORT)
    mock_upstream:start()

    local mock_s3_impl = assert(io.open("spec-ee/fixtures/mock_s3.lua")):read("a")

    mock_s3 = http_mock.new(S3PORT, mock_s3_impl, {
      dicts = {
        objects = "10m",
        metadata = "10m",
      },
      prefix = "servroot_mock_s3",
      log_opts = {
        req_body = true,
      }
    })
  end)

  lazy_teardown(function()
    assert(mock_upstream:stop())
  end)

  before_each(function()
    assert(mock_s3:start())
  end)

  after_each(function()
    mock_s3:clean()
    assert(mock_s3:stop())
  end)

  for _, exporter_role in ipairs{"CP", "DP"} do
    for _, fallback_export_s3_config in ipairs{true, false} do
      describe("upload from " .. exporter_role .. " fallback_export_s3_config:" .. tostring(fallback_export_s3_config), function()
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
            cluster_fallback_export_s3_config = (fallback_export_s3_config and exporter_role == "CP")
              and cluster_fallback_export_s3_config or nil,
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
            cluster_fallback_export_s3_config = (fallback_export_s3_config and exporter_role == "DP")
              and cluster_fallback_export_s3_config or nil,
            cluster_fallback_config_export_delay = 2,
            cluster_control_plane = "127.0.0.1:9005",
            proxy_listen = "127.0.0.1:" .. DP1PORT, -- otherwise it won't start
            stream_listen = "off",
          }))
          assert(helpers.start_kong({
            role = "data_plane",
            database = "off",
            prefix = "servroot3",
            cluster_cert = "spec/fixtures/kong_clustering.crt",
            cluster_cert_key = "spec/fixtures/kong_clustering.key",
            lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
            cluster_fallback_config_storage = exporter_role == "DP" and  cluster_fallback_config_storage or nil,
            cluster_fallback_config_export = exporter_role == "DP" and "on" or "off",
            cluster_fallback_export_s3_config = (fallback_export_s3_config and exporter_role == "DP")
              and cluster_fallback_export_s3_config or nil,
            cluster_fallback_config_export_delay = 2,
            cluster_control_plane = "127.0.0.1:9005",
            proxy_listen = "127.0.0.1:" .. DP2PORT, -- otherwise it won't start
            stream_listen = "off",
          }))
          client = helpers.admin_client()
        end)

        after_each(function ()
          helpers.stop_kong(nil, true)
          helpers.stop_kong("servroot2", true)
          helpers.stop_kong("servroot3", true)
        end)

        it("test", function()
          configure(client)

          -- we at least need to wait for this long
          -- sleep to try less times
          ngx.sleep(2)

          wait_for_final_config(mock_s3, fallback_export_s3_config)
        end)
      end)
    end
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
      }))
    end)


    after_each(function ()
      helpers.stop_kong("servroot3", true)
    end)


    it("test", function()
      local client = helpers.proxy_client(nil, S3PORT)
      assert(client:send {
        method = "PUT",
        path = "/test_bucket/test_prefix/" .. KONG_VERSION .. "/config.json",
        body = test_config,
        headers = {
          ["Content-Type"] = "application/json",
        }
      })

      local req
      mock_s3.eventually:has_request_satisfy(function(req_)
        assert.same(req_.method, "GET")
        assert.same("/test_bucket/test_prefix/" .. KONG_VERSION .. "/config.json", req_.uri)
        req = req_
      end)

      assert.Nil(req.body)
      verify_aws_request(req.headers)

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
