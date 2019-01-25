local helpers = require "spec.helpers"
local cjson   = require "cjson"


local RESPONSE_CODE    = 504
local RESPONSE_MESSAGE = "The upstream server is timing out"


describe("Proxy errors Content-Type", function()
  local client

  lazy_setup(function()
    helpers.dao:truncate_table("apis")

    assert(helpers.dao.apis:insert {
      name                     = "api-1",
      methods                  = "GET",
      upstream_url             = "http://konghq.com:81",
      upstream_connect_timeout = 1,
    })

    assert(helpers.start_kong {
      prefix             = helpers.test_conf.prefix,
      nginx_conf         = "spec/fixtures/custom_nginx.template",
      error_default_type = "text/html",
    })
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  it("no Accept header uses error_default_type", function()
    local res = assert(client:send {
      method  = "GET",
      path    = "/",
      headers = {
        accept = nil,
      }
    })

    local body = assert.res_status(RESPONSE_CODE, res)
    local html_template = "<html><head><title>Kong Error</title></head>" ..
                          "<body><h1>Kong Error</h1><p>%s.</p>"          ..
                          "</body></html>"
    local html_message = string.format(html_template, RESPONSE_MESSAGE)
    assert.equal(html_message, body)
  end)

  describe("", function()
    lazy_setup(function()
      assert(helpers.kong_exec(("restart --conf %s --nginx-conf %s"):format(
                               helpers.test_conf_path,
                               "spec/fixtures/custom_nginx.template")))
    end)

    it("default error_default_type = text/plain", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/",
        headers = {
          accept = nil,
        }
      })

      local body = assert.res_status(RESPONSE_CODE, res)
      assert.equal(RESPONSE_MESSAGE, body)
    end)

    describe("Accept header modified Content-Type", function()
      it("text/html", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            accept = "text/html",
          }
        })

        local body = assert.res_status(RESPONSE_CODE, res)
        local html_template = "<html><head><title>Kong Error</title></head>" ..
                              "<body><h1>Kong Error</h1><p>%s.</p>"          ..
                              "</body></html>"
        local html_message = string.format(html_template, RESPONSE_MESSAGE)
        assert.equal(html_message, body)
      end)

      it("application/json", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            accept = "application/json",
          }
        })

        local body = assert.res_status(RESPONSE_CODE, res)
        local json = cjson.decode(body)
        assert.equal(RESPONSE_MESSAGE, json.message)
      end)

      it("application/xml", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            accept = "application/xml",
          }
        })

        local body = assert.res_status(RESPONSE_CODE, res)
        local xml_template = '<?xml version="1.0" encoding="UTF-8"?>\n' ..
                             '<error><message>%s</message></error>'
        local xml_message = string.format(xml_template, RESPONSE_MESSAGE)
        assert.equal(xml_message, body)
      end)
    end)
  end)
end)
