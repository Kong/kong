-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME = "redirect"
local null = ngx.null

-- helper function to validate data against a schema
local validate
do
    local validate_entity = require("spec.helpers").validate_plugin_config_schema
    local plugin_schema = require("kong.plugins." .. PLUGIN_NAME .. ".schema")

    function validate(data)
        return validate_entity(data, plugin_schema)
    end
end

describe("Plugin: redirect (schema)", function()
    it("should accept a valid status_code", function()
        local ok, err = validate({
            status_code = 404,
            location = "https://example.com"
        })
        assert.is_nil(err)
        assert.is_truthy(ok)
    end)

    it("should accept a valid location", function()
        local ok, err = validate({
            location = "https://example.com"
        })
        assert.is_nil(err)
        assert.is_truthy(ok)
    end)



    describe("errors", function()
        it("status_code should only accept integers", function()
            local ok, err = validate({
                status_code = "abcd",
                location = "https://example.com"
            })
            assert.falsy(ok)
            assert.same("expected an integer", err.config.status_code)
        end)

        it("status_code is not nullable", function()
            local ok, err = validate({
                status_code = null,
                location = "https://example.com"
            })
            assert.falsy(ok)
            assert.same("required field missing", err.config.status_code)
        end)

        it("status_code < 100", function()
            local ok, err = validate({
                status_code = 99,
                location = "https://example.com"
            })
            assert.falsy(ok)
            assert.same("value should be between 100 and 599", err.config.status_code)
        end)

        it("status_code > 599", function()
            local ok, err = validate({
                status_code = 600,
                location = "https://example.com"
            })
            assert.falsy(ok)
            assert.same("value should be between 100 and 599", err.config.status_code)
        end)

        it("location is required", function()
            local ok, err = validate({
                status_code = 301
            })
            assert.falsy(ok)
            assert.same("required field missing", err.config.location)
        end)

        it("location must be a url", function()
            local ok, err = validate({
                status_code = 301,
                location = "definitely_not_a_url"
            })
            assert.falsy(ok)
            assert.same("missing host in url", err.config.location)
        end)

        it("incoming_path must be a boolean", function()
            local ok, err = validate({
                status_code = 301,
                location = "https://example.com",
                keep_incoming_path = "invalid"
            })
            assert.falsy(ok)
            assert.same("expected a boolean", err.config.keep_incoming_path)
        end)
    end)
end)
