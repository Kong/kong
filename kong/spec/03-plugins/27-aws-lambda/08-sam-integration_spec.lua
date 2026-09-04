local helpers = require "spec.helpers"
local sam = require "spec.fixtures.aws-sam"
local utils = require "spec.helpers.perf.utils"

local sam_describe
do
  local arch_type = sam.get_os_architecture()
  local is_sam_installed, _ = sam.is_sam_installed()
  if arch_type ~= "aarch64" and is_sam_installed then
    sam_describe = describe
  else
    sam_describe = pending
  end
end

-- SAM tool can only run on x86_64/arm64 platform so bypass when aarch64
if sam.get_os_architecture() ~= "aarch64" then
  for _, strategy in helpers.each_strategy() do
    sam_describe("Plugin: AWS Lambda with SAM local lambda service [#" .. strategy .. "]", function()
      local proxy_client
      local admin_client
      local sam_port

      lazy_setup(function ()
        local ret
        ret, sam_port = sam.start_local_lambda()
        if not ret then
          assert(false, sam_port)
        end

        helpers.pwait_until(function()
          local _, err = utils.wait_output("curl -s http://localhost:" .. sam_port .. "/2015-03-31/functions/HelloWorldFunction/invocations -d '{}'")
          assert.is_nil(err)
        end, 1200)

        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        }, { "aws-lambda" })

        local route1 = bp.routes:insert {
          hosts = { "lambda.test" },
        }

        bp.plugins:insert {
          name     = "aws-lambda",
          route    = { id = route1.id },
          config   = {
            host          = "localhost",
            port          = sam_port,
            disable_https = true,
            aws_key       = "mock-key",
            aws_secret    = "mock-secret",
            aws_region    = "us-east-1",
            function_name = "HelloWorldFunction",
            log_type      = "None",
          },
        }

        local route2 = bp.routes:insert {
          hosts = { "lambda2.test" },
        }

        bp.plugins:insert {
          name     = "aws-lambda",
          route    = { id = route2.id },
          config   = {
            host          = "localhost",
            port          = sam_port,
            disable_https = true,
            aws_key       = "mock-key",
            aws_secret    = "mock-secret",
            aws_region    = "us-east-1",
            function_name = "HelloWorldFunction",
            log_type      = "None",
            is_proxy_integration = true,
          },
        }
      end)

      lazy_teardown(function()
        sam.stop_local_lambda()
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
        admin_client = helpers.admin_client()
      end)

      after_each(function ()
        proxy_client:close()
        admin_client:close()
      end)

      sam_describe("with local HTTP endpoint", function ()
        lazy_setup(function()
          assert(helpers.start_kong({
            database   = strategy,
            plugins = "aws-lambda",
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }, nil, nil, nil))
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        it("invoke a simple function", function ()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/",
            headers = {
              host = "lambda.test"
            }
          })
          assert.res_status(200, res)
        end)

        it("can extract proxy response correctly", function ()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/",
            headers = {
              host = "lambda2.test"
            }
          })
          assert.res_status(201, res)
          local body = assert.response(res).has.jsonbody()
          assert.equal("hello world", body.message)
        end)
      end)
    end)
  end
end
