-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fmt = string.format
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_utils = require "pl.utils"

local mock_server_port = helpers.get_available_port()

local TEST_PG_USER = os.getenv("KONG_TEST_PG_USER") or helpers.test_conf.pg_user

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

        location = /v1/secret/data/db {
          content_by_lua_block {
            ngx.req.read_body()
            ngx.status = 200
            ngx.header["Content-Type"] = "application/json"
            ngx.say('{"data": {"data": {"user": "%s"}}}')
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

        location = /v1/auth/approle/login {
          content_by_lua_block {
            ngx.req.read_body()
            local body = ngx.req.get_body_data()
            local cjson = require "cjson"
            local json = cjson.decode(body)
            ngx.log(ngx.DEBUG, body)
            if json.secret_id == "test-secret-id" then
              ngx.status = 200
              ngx.header["Content-Type"] = "application/json"
              ngx.say('{"auth": {"client_token": "mock_token"}}')
            else
              ngx.status = 403
              ngx.header["Content-Type"] = "application/json"
              ngx.say('{"message": "invalid secret_id"}')
            end
          }
        }

        location = /v1/sys/wrapping/unwrap {
          content_by_lua_block {
            ngx.req.read_body()
            local wrapping_token = ngx.req.get_headers()["X-Vault-Token"]
            if wrapping_token and wrapping_token == "test_wrapping_token" then
              ngx.status = 200
              ngx.header["Content-Type"] = "application/json"
              ngx.say('{"data": {"secret_id": "test-secret-id"}}')
            else
              ngx.status = 500
              ngx.header["Content-Type"] = "application/json"
              ngx.say('{"message": "invalid wrapping token"}')
            end
          }
        }
      }
    ]], mock_server_port, mock_server_port, TEST_PG_USER),
  }
}

local function setup_env_var(override_env_vars)
  local mock_env = {
    KONG_LUA_SSL_TRUSTED_CERTIFICATE = "spec/fixtures/kong_spec.crt",
    -- KONG_LUA_SSL_TRUSTED_CERTIFICATE = "spec/fixtures/kong_clustering_ca.crt",
    KONG_VAULT_HCV_PROTOCOL = "https",
    KONG_VAULT_HCV_HOST = "localhost",
    KONG_VAULT_HCV_PORT = tostring(mock_server_port),
    KONG_VAULT_HCV_KV = "v2",
    KONG_PREFIX = "servroot_mock_hcv_command_line",
  }

  for k, v in pairs(override_env_vars) do
    mock_env[k] = v
  end

  local original_env = {}
  local empty_original_env = {}

  for k, v in pairs(mock_env) do
    local orig_env = os.getenv(k)
    if orig_env then
      original_env[k] = orig_env
    else
      empty_original_env[k] = true
    end

    helpers.setenv(k, v)
  end

  return function()
    for k, v in pairs(original_env) do
      helpers.setenv(k, v)
    end

    for k in pairs(empty_original_env) do
      helpers.unsetenv(k)
    end
  end
end


for _, strategy in helpers.each_strategy() do
  describe("HCV backend with self signed SSL certificate", function()
    local mock_tmp_kube_auth_token
    lazy_setup(function()
      helpers.get_db_utils(strategy, {}) -- runs migrations

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
    end)

    after_each(function()
      helpers.clean_prefix("servroot_mock_hcv_command_line")
    end)

    it("worked in CLI with kubernetes auth method", function()
      local env_resetter = setup_env_var({
        KONG_VAULT_HCV_AUTH_METHOD = "kubernetes",
        KONG_VAULT_HCV_KUBE_API_TOKEN_FILE = mock_tmp_kube_auth_token,
      })

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

    it("worked in CLI with approle auth method", function()
      local env_resetter = setup_env_var({
        KONG_VAULT_HCV_AUTH_METHOD = "approle",
        KONG_VAULT_HCV_APPROLE_ROLE_ID = "test-role-id",
        KONG_VAULT_HCV_APPROLE_SECRET_ID = "test-secret-id",
      })

      finally(function()
        env_resetter()
      end)

      -- Should be able to use CLI
      assert(helpers.kong_exec("vault get {vault://hcv/kong} --vv"))
    end)

    it("worked in CLI with approle auth method when database is also vault referenced", function()
      local env_resetter = setup_env_var({
        KONG_PG_USER = "{vault://hcv/db/user}",
        KONG_VAULT_HCV_AUTH_METHOD = "approle",
        KONG_VAULT_HCV_APPROLE_ROLE_ID = "test-role-id",
        KONG_VAULT_HCV_APPROLE_SECRET_ID = "test-secret-id",
      })

      finally(function()
        env_resetter()
      end)

      -- Should be able to use CLI
      assert(helpers.kong_exec("vault get {vault://hcv/kong} --vv"))
    end)

    it("worked in CLI with approle auth method and response wrapping file", function ()
      local tmp_file_name = pl_path.tmpname()
      pl_utils.writefile(tmp_file_name, "test_wrapping_token")

      local env_resetter = setup_env_var({
        KONG_PG_USER = "{vault://hcv/db/user}",
        KONG_VAULT_HCV_AUTH_METHOD = "approle",
        KONG_VAULT_HCV_APPROLE_ROLE_ID = "test-role-id",
        KONG_VAULT_HCV_APPROLE_SECRET_ID_FILE = tmp_file_name,
        KONG_VAULT_HCV_APPROLE_RESPONSE_WRAPPING = "true",
      })

      finally(function()
        env_resetter()
      end)

      -- Should be able to use CLI
      assert(helpers.kong_exec("vault get {vault://hcv/kong} --vv"))
    end)
  end)
end
