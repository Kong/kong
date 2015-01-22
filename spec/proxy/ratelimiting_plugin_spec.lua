local utils = require "apenode.tools.utils"
local cjson = require "cjson"

local kProxyURL = "http://localhost:8000/"

describe("RateLimiting Plugin", function()

    describe("Without authentication", function()
      it("should get blocked if exceeding limit by IP address", function()
        local response, status, headers = utils.get(kProxyURL.."get", {}, {host = "test5.com"})
        assert.are.equal(200, status)

        response, status, headers = utils.get(kProxyURL.."get", {}, {host = "test5.com"})
        assert.are.equal(200, status)

        response, status, headers = utils.get(kProxyURL.."get", {}, {host = "test5.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)
    end)

     describe("With authentication", function()
      it("should get blocked if exceeding limit by apikey", function()
        local response, status, headers = utils.get(kProxyURL.."get", {apikey = "apikey123"}, {host = "test6.com"})
        assert.are.equal(200, status)

        response, status, headers = utils.get(kProxyURL.."get", {apikey = "apikey123"}, {host = "test6.com"})
        assert.are.equal(200, status)

        response, status, headers = utils.get(kProxyURL.."get", {apikey = "apikey123"}, {host = "test6.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)
    end)

    describe("With authentication and overridden application plugin", function()
      it("should get blocked if exceeding rate limiting", function()
        local response, status, headers = utils.get(kProxyURL.."get", {apikey = "apikey124"}, {host = "test6.com"})
        assert.are.equal(200, status)

        response, status, headers = utils.get(kProxyURL.."get", {apikey = "apikey124"}, {host = "test6.com"})
        assert.are.equal(200, status)

        response, status, headers = utils.get(kProxyURL.."get", {apikey = "apikey124"}, {host = "test6.com"})
        assert.are.equal(200, status)

        response, status, headers = utils.get(kProxyURL.."get", {apikey = "apikey124"}, {host = "test6.com"})
        assert.are.equal(200, status)

        response, status, headers = utils.get(kProxyURL.."get", {apikey = "apikey124"}, {host = "test6.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)
    end)

end)
