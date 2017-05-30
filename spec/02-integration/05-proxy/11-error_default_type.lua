local helpers = require "spec.helpers"
local cjson = require "cjson"
local format = string.format

local function start(config)
  return function()
    helpers.dao.apis:insert {
      name = "api-1",
      upstream_url = "http://127.0.0.1:3333/",
      hosts = {
        "example.com",
      }
    }

    config = config or {}
    config.nginx_conf = "spec/fixtures/custom_nginx.template"

    assert(helpers.start_kong(config))
  end
end

describe("Error Default Type", function()
  local client

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  describe("(with default configuration values)", function()

    setup(start {
      nginx_conf         = "spec/fixtures/custom_nginx.template",
    })

    teardown(helpers.stop_kong)

    it("should return error message in plain text", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/",
        headers = {
          accept = nil,
          host   = "example.com",
        }
      })

      local body = assert.response(res).has_status(502)
      assert.equal("An invalid response was received from the upstream server", body)
    end)
  end)

  describe("(with error_default_type = text/plain)", function()

    setup(start {
      nginx_conf         = "spec/fixtures/custom_nginx.template",
      error_default_type = "text/plain",
    })

    teardown(helpers.stop_kong)

    it("should return error message in plain text", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/",
        headers = {
          accept = nil,
          host   = "example.com",
        }
      })

      local body = assert.response(res).has_status(502)
      assert.equal("An invalid response was received from the upstream server", body)
    end)
  end)

  describe("(with error_default_type = application/json)", function()

    setup(start {
      nginx_conf         = "spec/fixtures/custom_nginx.template",
      error_default_type = "application/json",
    })

    teardown(helpers.stop_kong)

    it("should return error message in json", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/",
        headers = {
          accept = nil,
          host   = "example.com",
        }
      })

      local body = assert.response(res).has_status(502)
      local json = cjson.decode(body)
      assert.equal("An invalid response was received from the upstream server", json.message)
    end)
  end)

  describe("(with error_default_type = application/xml)", function()

    setup(start {
      nginx_conf         = "spec/fixtures/custom_nginx.template",
      error_default_type = "application/xml",
    })

    teardown(helpers.stop_kong)

    it("should return error message in xml", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/",
        headers = {
          accept = nil,
          host   = "example.com",
        }
      })

      local body = assert.response(res).has_status(502)
      local xml = '<?xml version="1.0" encoding="UTF-8"?>\n<error><message>%s</message></error>'
      assert.equal(format(xml, "An invalid response was received from the upstream server"), body)
    end)
  end)

  describe("(with error_default_type = text/html)", function()

    setup(start {
      nginx_conf         = "spec/fixtures/custom_nginx.template",
      error_default_type = "text/html",
    })

    teardown(helpers.stop_kong)

    it("should return error message in html", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/",
        headers = {
          accept = nil,
          host   = "example.com",
        }
      })

      local body = assert.response(res).has_status(502)
      local html = '<html><head><title>Kong Error</title></head><body><h1>Kong Error</h1><p>%s.</p></body></html>'
      assert.equal(format(html, "An invalid response was received from the upstream server"), body)
    end)
  end)
end) 
