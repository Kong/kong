local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("plugin triggering #" .. strategy, function()
    lazy_setup(function()
      local bp = assert(helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
      }))

      assert(bp.services:insert {})
      assert(bp.routes:insert({
        protocols = { "http" },
        paths = { "/" }
      }))

      local kong_prefix = helpers.test_conf.prefix

      assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template",
          database = strategy,
          plugins = "bundled,reports-api,go-hello,py-hello",
          pluginserver_names = "test-go,test-py",
          pluginserver_test_go_socket = kong_prefix .. "/go-hello.socket",
          pluginserver_test_go_query_cmd = helpers.external_plugins_path .. "/go/go-hello -dump -kong-prefix " .. kong_prefix,
          pluginserver_test_go_start_cmd = helpers.external_plugins_path .. "/go/go-hello -kong-prefix " .. kong_prefix,
          pluginserver_test_py_socket = kong_prefix .. "/py-hello.socket",
          pluginserver_test_py_query_cmd = helpers.external_plugins_path .. "/py/py-hello.py --dump",
          pluginserver_test_py_start_cmd = helpers.external_plugins_path .. "/py/py-hello.py --socket-name py-hello.socket --kong-prefix " .. kong_prefix,
      }))

      local admin_client = helpers.admin_client()

      local res = admin_client:post("/plugins", {
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          name = "go-hello",
          config = {
            message = "Kong!"
          }
        }
      })
      assert.res_status(201, res)

      res = admin_client:post("/plugins", {
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          name = "py-hello",
          config = {
            message = "Kong!"
          }
        }
      })
      assert.res_status(201, res)
    end)

    lazy_teardown(function()
        helpers.stop_kong()
    end)

    it("executes external plugins [golang, python]", function()
      local proxy_client = assert(helpers.proxy_client())
      local res = proxy_client:get("/")
      assert.res_status(200, res)
      local h = assert.response(res).has.header("x-hello-from-go")
      assert.matches("Go says Kong! to", h)
      h = assert.response(res).has.header("x-hello-from-python")
      assert.matches("Python says Kong! to", h)
    end)
  end)
end
