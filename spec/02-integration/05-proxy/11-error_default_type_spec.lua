local helpers = require "spec.helpers"
local cjson   = require "cjson"


local S502_MESSAGE = "An invalid response was received from the upstream server"
local RELOAD_DELAY = 1.0


describe("error_default_type", function()
  local client

  setup(function()
    helpers.dao:truncate_tables()

    assert(helpers.dao.apis:insert {
      name         = "api-1",
      upstream_url = helpers.mock_upstream_url .. "/status/500",
      hosts        = {
        "example.com",
      },
    })

    assert(helpers.start_kong {
      prefix     = helpers.test_conf.prefix,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })
  end)

  teardown(function()
    helpers.stop_kong(helpers.test_conf.prefix, true)
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  describe("request `Accept` is missing", function()
    describe("(default)", function()
      setup(function()
        assert(helpers.kong_exec("reload", {
          prefix             = helpers.test_conf.prefix,
          nginx_conf         = "spec/fixtures/custom_nginx.template",
        }))

        ngx.sleep(RELOAD_DELAY)
      end)

      it("returns error messages in plain text", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            accept = nil,
            host   = "example.com",
          }
        })

        local body = assert.res_status(502, res)
        assert.equal(S502_MESSAGE, body)
      end)
    end)

    describe("(text/plain)", function()
      setup(function()
        assert(helpers.kong_exec("reload", {
          prefix             = helpers.test_conf.prefix,
          nginx_conf         = "spec/fixtures/custom_nginx.template",
          error_default_type = "text/plain",
        }))

        ngx.sleep(RELOAD_DELAY)
      end)

      it("returns error messages in plain text", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            accept = nil,
            host   = "example.com",
          }
        })

        local body = assert.res_status(502, res)
        assert.equal(S502_MESSAGE, body)
      end)
    end)

    describe("(application/json)", function()
      setup(function()
        assert(helpers.kong_exec("reload", {
          prefix             = helpers.test_conf.prefix,
          nginx_conf         = "spec/fixtures/custom_nginx.template",
          error_default_type = "application/json",
        }))

        ngx.sleep(RELOAD_DELAY)
      end)

      it("returns error messages in JSON", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            accept = nil,
            host   = "example.com",
          }
        })

        local body = assert.res_status(502, res)
        local json = cjson.decode(body)
        assert.equal("An invalid response was received from the upstream server",
                     json.message)
      end)
    end)

    describe("(application/xml)", function()
      setup(function()
        assert(helpers.kong_exec("reload", {
          prefix             = helpers.test_conf.prefix,
          nginx_conf         = "spec/fixtures/custom_nginx.template",
          error_default_type = "application/xml",
        }))

        ngx.sleep(RELOAD_DELAY)
      end)

      it("returns error messages in XML", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            accept = nil,
            host   = "example.com",
          }
        })

        local body = assert.res_status(502, res)

        local xml_template = '<?xml version="1.0" encoding="UTF-8"?>\n' ..
                             '<error><message>%s</message></error>'
        local xml_message = string.format(xml_template, S502_MESSAGE)

        assert.equal(xml_message, body)
      end)
    end)

    describe("(text/html)", function()
      setup(function()
        assert(helpers.kong_exec("reload", {
          prefix             = helpers.test_conf.prefix,
          nginx_conf         = "spec/fixtures/custom_nginx.template",
          error_default_type = "text/html",
        }))

        ngx.sleep(RELOAD_DELAY)
      end)

      it("returns error messages in HTML", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            accept = nil,
            host   = "example.com",
          }
        })

        local body = assert.res_status(502, res)

        local html_template = "<html><head><title>Kong Error</title></head>" ..
                              "<body><h1>Kong Error</h1><p>%s.</p>"          ..
                              "</body></html>"
        local html_message = string.format(html_template, S502_MESSAGE)

        assert.equal(html_message, body)
      end)
    end)
  end)

  describe("request `Accept` is present", function()
    setup(function()
      assert(helpers.kong_exec("reload", {
        prefix             = helpers.test_conf.prefix,
        nginx_conf         = "spec/fixtures/custom_nginx.template",
        error_default_type = "text/plain",
      }))

      ngx.sleep(RELOAD_DELAY)
    end)

    it("returns error messages according to `Accept`", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            accept = "text/html",
            host   = "example.com",
          }
        })

        local body = assert.res_status(502, res)

        local html_template = "<html><head><title>Kong Error</title></head>" ..
                              "<body><h1>Kong Error</h1><p>%s.</p>"          ..
                              "</body></html>"
        local html_message = string.format(html_template, S502_MESSAGE)

        assert.equal(html_message, body)
    end)
  end)
end)
