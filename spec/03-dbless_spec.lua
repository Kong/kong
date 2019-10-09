local helpers = require "spec.helpers"


for _, plugin_name in ipairs({ "pre-function", "post-function" }) do

  describe("Plugin: " .. plugin_name .. " (dbless)", function()
    local admin_client

    setup(function()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = "off",
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
    end)


    describe("loading functions from declarative config", function()
      it("does not execute the function ( https://github.com/kong/kong/issues/5110 )", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/config",
          body = {
            config = [[
              "_format_version": "1.1"
              plugins:
              - name: "pre-function"
                config:
                  functions:
                  - | 
                      kong.log.err("foo")
                      kong.response.exit(418)
            ]]
          },
          headers = {
            ["Content-type"] = "application/json"
          }
        })
        assert.res_status(201, res)
      end)
    end)
  end)

end
