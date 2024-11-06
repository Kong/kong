require("spec.helpers")
local LOG_PHASE = require("kong.pdk.private.phases").phases.log

describe("compile_resource_attributes()", function()
    local mock_request
    local old_ngx
    local compile_resource_attributes

    setup(function()
        old_ngx = _G.ngx
        _G.ngx = {
            ctx = {
                KONG_PHASE = LOG_PHASE
            },
            req = {
              get_headers = function() return mock_request.headers end,
            },
            get_phase = function() return "log" end,
        }
        package.loaded["kong.pdk.request"] = nil
        package.loaded["kong.plugins.opentelemetry.utils"] = nil
        
        local pdk_request = require "kong.pdk.request"
        kong.request = pdk_request.new(kong)
        compile_resource_attributes = require "kong.plugins.opentelemetry.utils".compile_resource_attributes
    end)

    lazy_teardown(function()
        _G.ngx = old_ngx
    end)


    it("accepts valid template and valid string", function()
        mock_request = {
            headers = {
                host = "kong-test",
            },    
        }
        local resource_attributes = {
            ["valid_variable"] = "$(headers.host)",
            ["nonexist_variable"] = "$($@#)",
            ["valid_string"] = "valid",
        }
        local rendered_resource_attributes, err = compile_resource_attributes(resource_attributes)
        
        assert.is_nil(err)
        assert.same(rendered_resource_attributes["valid_variable"], "kong-test")

        -- take as a normal string if variable does not exist
        assert.same(rendered_resource_attributes["nonexist_variable"], "$($@#)")
        assert.same(rendered_resource_attributes["valid_string"], "valid")
    end)
end)
