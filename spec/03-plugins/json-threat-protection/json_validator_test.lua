describe("Json Threat Protection Validator Test Suite", function()

    local jtp
    local status
    local message

    setup(function()
        jtp = require "kong.plugins.json-threat-protection.json_validator"
        status = nil
        message = nil
    end)

    teardown(function()
        jtp = nil
        status = nil
        message = nil
    end)

    it("Test with valid json", function()
        local json = "{ \"test\": \"value\" }"
        status, message = jtp.execute(json, 10, 10, 10, 10, 10)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid json", function()
        local json = "{ \"te \"value\" }"
        status, message = jtp.execute(json, 10, 10, 10, 10, 10)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid ignored container depth", function()
        local json = "{\"level1\":\"value1\",\"level2\":{\"level3\":{\"three\":\"value3\"}}}"
        status, message = jtp.execute(json, 0, 10, 10, 10, 10)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid container depth", function()
        local json = "{\"level1\":\"value1\",\"level2\":{\"level3\":{\"three\":\"value3\"}}}"
        status, message = jtp.execute(json, 2, 10, 10, 10, 10)

        assert.equal(status, false)
        assert.equal(message, "JSONThreatProtection[ExceededContainerDepth]: Exceeded container depth, max 2 allowed.")
    end)

    it("Test with invalid ignored array element count", function()
        local json = "{\"array1\":[\"value1\",\"value2\",\"value3\"]}"
        status, message = jtp.execute(json, 10, 0, 0, 10, 10)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with valid json, invalid array element count", function()
        local json = "{\"array1\":[\"value1\",\"value2\",\"value3\"]}"
        status, message = jtp.execute(json, 10, 2, 10, 10, 10)

        assert.equal(status, false)
        assert.equal(message, "JSONThreatProtection[ExceededArrayElementCount]: Exceeded array element count, max 2 allowed, found 3.")
    end)

    it("Test with invalid ignored object entry count", function()
        local json = "{\"one\":\"value1\",\"two\":\"value2\",\"three\":\"value3\",\"four\":\"value4\"}"
        status, message = jtp.execute(json, 10, 10, 0, 10, 10)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with valid json, invalid object entry count", function()
        local json = "{\"one\":\"value1\",\"two\":\"value2\",\"three\":\"value3\",\"four\":\"value4\"}"
        status, message = jtp.execute(json, 10, 10, 2, 10, 10)

        assert.equal(status, false)
        assert.equal(message, "JSONThreatProtection[ExceededObjectEntryCount]: Exceeded object entry count, max 2 allowed, found 4.")
    end)

    it("Test with invalid ignored object name length", function()
        local json = "{\"longlongname\":\"value\"}"
        status, message = jtp.execute(json, 10, 10, 10, 0, 10)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with valid json, invalid object name length", function()
        local json = "{\"longlongname\":\"value\"}"
        status, message = jtp.execute(json, 10, 10, 10, 5, 10)

        assert.equal(status, false)
        assert.equal(message, "JSONThreatProtection[ExceededObjectEntryNameLength]: Exceeded object entry name length, max 5 allowed, found 12 (longlongname).")
    end)

    it("Test with invalid ignored string value length", function()
        local json = "{\"key\":\"this value is too long\"}"
        status, message = jtp.execute(json, 10, 10, 10, 10, 0)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with valid json, invalid string value length", function()
        local json = "{\"key\":\"this value is too long\"}"
        status, message = jtp.execute(json, 10, 10, 10, 10, 5)

        assert.equal(status, false)
        assert.equal(message, "JSONThreatProtection[ExceededStringValueLength]: Exceeded string value length, max 5 allowed, found 22 (this value is too long).")
    end)
end)
