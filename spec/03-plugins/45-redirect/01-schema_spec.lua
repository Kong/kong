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

    it("incoming_path can be 'ignore'", function()
        local ok, err = validate({
            status_code = 301,
            location = "https://example.com",
            incoming_path = "ignore"
        })
        assert.is_nil(err)
        assert.is_truthy(ok)
    end)

    it("incoming_path can be 'keep'", function()
        local ok, err = validate({
            status_code = 301,
            location = "https://example.com",
            incoming_path = "keep"
        })
        assert.is_nil(err)
        assert.is_truthy(ok)
    end)

    it("incoming_path can be 'merge'", function()
        local ok, err = validate({
            status_code = 301,
            location = "https://example.com",
            incoming_path = "merge"
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

        it("incoming_path must be a one_of value", function()
            local ok, err = validate({
                status_code = 301,
                location = "https://example.com",
                incoming_path = "invalid"
            })
            assert.falsy(ok)
            assert.same("expected one of: ignore, keep, merge", err.config.incoming_path)
        end)
    end)
end)
