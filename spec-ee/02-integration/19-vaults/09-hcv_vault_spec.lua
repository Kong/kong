-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fmt = string.format
local pl_path = require "pl.path"
local pl_file = require("pl.file")

local mock_server_port = helpers.get_available_port()

local fixtures = {
  http_mock = {
    mock_hcv_server = fmt([[
      server {
        listen %s ssl;
        listen [::]:%s ssl;

        ssl_certificate ../spec/fixtures/kong_spec.crt;
        ssl_certificate_key ../spec/fixtures/kong_spec.key;

        error_log logs/proxy.log debug;

        location = /v1/secret/data/kong {
          content_by_lua_block {
            ngx.req.read_body()
            ngx.status = 200
            ngx.header["Content-Type"] = "application/json"
            ngx.say('{"data": {"data": {"abc": "test"}}}')
          }
        }

        location = /v1/auth/kubernetes/login {
          content_by_lua_block {
            ngx.req.read_body()
            ngx.status = 200
            ngx.header["Content-Type"] = "application/json"
            ngx.say('{"auth": {"client_token": "mock_token"}}')
          }
        }


      }
    ]], mock_server_port, mock_server_port),
  }
}

local function setup_env_var(mock_token_path)
  local mock_env = {
    KONG_LUA_SSL_TRUSTED_CERTIFICATE = "spec/fixtures/kong_spec.crt",
    -- KONG_LUA_SSL_TRUSTED_CERTIFICATE = "spec/fixtures/kong_clustering_ca.crt",
    KONG_VAULT_HCV_PROTOCOL = "https",
    KONG_VAULT_HCV_HOST = "localhost",
    KONG_VAULT_HCV_PORT = tostring(mock_server_port),
    KONG_VAULT_HCV_KV = "v2",
    KONG_VAULT_HCV_AUTH_METHOD = "kubernetes",
    KONG_VAULT_HCV_KUBE_API_TOKEN_FILE = mock_token_path,
    KONG_PREFIX = "servroot_mock_hcv_command_line",
  }

  local original_env = {}

  for i, v in ipairs({
    "KONG_LUA_SSL_TRUSTED_CERTIFICATE",
    "KONG_VAULT_HCV_PROTOCOL",
    "KONG_VAULT_HCV_HOST",
    "KONG_VAULT_HCV_PORT",
    "KONG_VAULT_HCV_KV",
    "KONG_VAULT_HCV_AUTH_METHOD",
    "KONG_VAULT_HCV_KUBE_API_TOKEN_FILE",
    "KONG_PREFIX",
  }) do
    original_env[v] = os.getenv(v)
    helpers.setenv(v, mock_env[v])
  end

  return function()
    for k, v in pairs(original_env) do
      helpers.setenv(k, v)
    end
  end
end


for _, strategy in helpers.each_strategy() do
  describe("HCV backend with self signed SSL certificate", function()
    local mock_tmp_kube_auth_token
    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy, {
      }) -- runs migrations

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        log_level = "debug",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_spec.crt",
      }, nil, nil, fixtures))

      mock_tmp_kube_auth_token = pl_path.tmpname()
      pl_file.write(mock_tmp_kube_auth_token, "mock_token")
    end)

    lazy_teardown(function()
      pl_file.delete(mock_tmp_kube_auth_token)
      helpers.stop_kong()
      helpers.stop_kong("servroot_mock_hcv_command_line")
    end)

    it("worked in CLI", function()
      local env_resetter = setup_env_var(mock_tmp_kube_auth_token)

      finally(function()
        env_resetter()
      end)

      -- succeed fetching the mocked secret when using the correct trusted self-signed certificate
      assert(helpers.kong_exec("vault get {vault://hcv/kong} --vv"))

      -- set a wrong trusted certificate
      local old_trusted_cert = os.getenv("KONG_LUA_SSL_TRUSTED_CERTIFICATE")
      helpers.setenv("KONG_LUA_SSL_TRUSTED_CERTIFICATE", "spec/fixtures/kong_clustering.crt")
      assert.falsy(helpers.kong_exec("vault get {vault://hcv/kong} --vv"))
      helpers.setenv("KONG_LUA_SSL_TRUSTED_CERTIFICATE", old_trusted_cert)
    end)
  end)
end
