local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local send_content_types = require "spec.integration.admin_api.helpers"

describe("Admin API", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/plugins_configurations/", function()

    describe("POST", function()

      it("should handle complex values", function()

        -- Create the API
        local api = send_content_types(spec_helper.API_URL.."/apis/", "POST", {
          name="Plugins Configurations POST tests",
          public_dns="api.mockbin.com",
          target_url="http://mockbin.com"
        }, 201, nil, {drop_db=true})

        local response, status = http_client.post(spec_helper.API_URL.."/apis/"..api.id.."/plugins/", {
          api_id = api.id,
          name = "request_transformer",
          ["value.add.headers"] = "x-new-header:some_value, x-another-header:some_value",
          ["value.add.querystring"] = "new-param:some_value, another-param:some_value",
          ["value.add.form"] = "new-form-param:some_value, another-form-param:some_value",
          ["value.remove.headers"] = "x-toremove, x-another-one",
          ["value.remove.querystring"] = "param-toremove, param-another-one",
          ["value.remove.form"] = "formparam-toremove"
        })

        local body = json.decode(response)

        assert.are.equal(api.id, body.api_id)
        assert.are.equal("request_transformer", body.name)
        assert.are.equal({ ["x-new-header"] = "some_value", ["x-another-header"] = "some_value"}, body.value.add.headers)
        assert.are.equal({ ["new-param"] = "some_value", ["another-param"] = "some_value"}, body.value.add.querystring)
        assert.are.equal({ ["form-param"] = "some_value", ["another-form-param"] = "some_value"}, body.value.add.form)
        assert.are.equal({ "x-to-remove", "x-another-one" }, body.value.remove.headers)
        assert.are.equal({ "param-toremove", "param-another-one" }, body.value.remove.querystring)
        assert.are.equal({ "formparam-toremove" }, body.value.remove.form)

      end)
    end)
  end)

end)
