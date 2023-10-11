-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_file = require "pl.file"
local helpers = require "spec.helpers"

local aws_region = os.getenv("RUNNER_AWS_REGION")
for _, strategy in helpers.each_strategy() do

describe("Kong startup with AWS Vault: ", function ()
  lazy_setup(function()
    local _ = helpers.get_db_utils()
    helpers.setenv("AWS_REGION", aws_region)
    helpers.setenv("KONG_LICENSE_DATA", pl_file.read("spec-ee/fixtures/mock_license.json"))
  end)

  lazy_teardown(function ()
    helpers.unsetenv("AWS_REGION")
    helpers.unsetenv("KONG_LICENSE_DATA")
  end)

  describe("credential fetching in multiple scenarios: ", function ()
    it("should start Kong with correct EC2 profile IAM role", function ()
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        log_level = "{vault://aws/gw-test-vault-test-secret/log_level}",
        plugins = "bundled",
        vaults = "bundled",
        vault_aws_region = aws_region,
      }, nil, nil, nil))

      finally(function ()
        assert(helpers.stop_kong())
      end)
    end)

    it("should start Kong with role assuming", function ()
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        log_level = "{vault://aws/gw-test-vault-test-secret/log_level}",
        plugins = "bundled",
        vaults = "bundled",
        vault_aws_region = aws_region,
        vault_aws_assume_role_arn = "arn:aws:iam::267914366688:role/gw-test-test-sm-read-role", -- TODO: change to the correct role
      }, nil, nil, nil))

      finally(function ()
        assert(helpers.stop_kong())
      end)
    end)
  end)
end)

for _, strategy in helpers.each_strategy() do
  describe("[#".. strategy .. "] " .. "Create AWS Vault via Admin API: ", function ()
    local proxy_client
    local admin_client

    helpers.setenv("AWS_REGION", aws_region)
    helpers.setenv("KONG_LICENSE_DATA", pl_file.read("spec-ee/fixtures/mock_license.json"))

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "vaults",
      }, { "request-transformer-advanced" })

      local service = assert(bp.services:insert {
        name = "example-service",
        host = "echo_server",
        protocol = "http",
        port = 10001,
      })

      assert(bp.routes:insert {
        hosts = { "example.com" },
        service   = service,
      })

      local fixtures = {
        dns_mock = helpers.dns_mock.new(),
        http_mock = {
          echo_server = [[
            server {
                server_name echo_server;
                listen 10001;

                location ~ "/" {
                  content_by_lua_block {
                    local cjson = require "cjson"
                    local headers = ngx.req.get_headers(0)
                    ngx.say(cjson.encode({headers=headers}))
                  }
                }
            }
          ]]
        },
      }

      fixtures.dns_mock:A {
        name = "echo_server",
        address = "127.0.0.1",
      }

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = "bundled, request-transformer-advanced",
        vaults     = "bundled",
        vault_aws_region = aws_region,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function ()
      helpers.unsetenv("AWS_REGION")
      helpers.unsetenv("KONG_LICENSE_DATA")
      proxy_client:close()
      admin_client:close()
      helpers.stop_kong()
    end)

    it("should create and use plugin with vault secret value correctly", function ()
      local res = assert(admin_client:send({
        method = "POST",
        path = "/plugins",
        body = {
          name = "request-transformer-advanced",
          config = {
            add = {
              headers = { "{vault://aws/gw-test-vault-test-secret/request_transformer_add_headers}" },
            },
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))
      assert.response(res).has.status(201)
      local _ = assert.response(res).has.jsonbody()

      helpers.wait_for_all_config_update()

      local res = assert(proxy_client:send({
        method = "GET",
        path = "/testpath",
        headers = {
          ["Host"] = "example.com",
        }
      }))

      assert.response(res).has.status(200)
      local headers = assert.response(res).has.jsonbody().headers
      assert.same("secret-value", headers["x-secret-header"])
    end)
  end)
end

describe("Kong Vault Command with AWS Vault: ", function ()
  lazy_setup(function()
    helpers.setenv("AWS_REGION", aws_region)
    helpers.setenv("KONG_LICENSE_DATA", pl_file.read("spec-ee/fixtures/mock_license.json"))
  end)

  lazy_teardown(function ()
    helpers.unsetenv("AWS_REGION")
    helpers.unsetenv("KONG_LICENSE_DATA")
    helpers.clean_prefix()
  end)

  it("should fetch correct value", function ()
    local ok, _, stdout = helpers.kong_exec("vault get aws/gw-test-vault-test-secret/secret_key", {
      log_level = "error",
      prefix = helpers.test_conf.prefix,
      vault_aws_region = aws_region,
    })
    assert.matches("secret_value", stdout, nil, true)
    assert.is_true(ok)
  end)

  it("should fetch the correct value with role assuming", function ()
    local ok, _, stdout = helpers.kong_exec("vault get aws/gw-test-vault-test-secret/secret_key", {
      log_level = "error",
      prefix = helpers.test_conf.prefix,
      vault_aws_region = aws_region,
      vault_aws_assume_role_arn = "arn:aws:iam::267914366688:role/gw-test-test-sm-read-role", -- TODO: change to the correct role
    })
    assert.matches("secret_value", stdout, nil, true)
    assert.is_true(ok)
  end)
end)

end
