local meta = require "kong.meta"
local responses = require "kong.tools.responses"

describe("Response helpers", function()
  local old_ngx = _G.ngx
  local snapshot
  local stubbed_ngx

  before_each(function()
    snapshot = assert:snapshot()
    stubbed_ngx = {
      header = {},
      say = function(...) return old_ngx.say(...) end,
      exit = function(...) return old_ngx.exit(...) end,
      log = function(...) return old_ngx.log(...) end,
    }
    _G.ngx = setmetatable(stubbed_ngx, {__index = old_ngx})
    stub(stubbed_ngx, "say")
    stub(stubbed_ngx, "exit")
    stub(stubbed_ngx, "log")
  end)

  after_each(function()
    snapshot:revert()
    _G.ngx = old_ngx
  end)

  it("has a list of the main http status codes used in Kong", function()
    assert.is_table(responses.status_codes)
  end)
  it("is callable via `send_HTTP_STATUS_CODE`", function()
    for status_code_name, status_code in pairs(responses.status_codes) do
      assert.has_no.errors(function()
        responses["send_" .. status_code_name]()
      end)
    end
  end)
  it("sets the correct ngx values and call ngx.say and ngx.exit", function()
    responses.send_HTTP_OK("OK")
    assert.equal(ngx.status, responses.status_codes.HTTP_OK)
    assert.equal(meta._SERVER_TOKENS, ngx.header["Server"])
    assert.equal("application/json; charset=utf-8", ngx.header["Content-Type"])
    assert.stub(ngx.say).was.called() -- set custom content
    assert.stub(ngx.exit).was.called() -- exit nginx (or continue to the next context if 200)
  end)
  it("send the content as a JSON string with a `message` property if given a string", function()
    responses.send_HTTP_OK("OK")
    assert.stub(ngx.say).was.called_with("{\"message\":\"OK\"}")
  end)
  it("sends the content as a JSON string if given a table", function()
    responses.send_HTTP_OK({success = true})
    assert.stub(ngx.say).was.called_with("{\"success\":true}")
  end)
  it("calls `ngx.exit` with the corresponding status_code", function()
    for status_code_name, status_code in pairs(responses.status_codes) do
      assert.has_no.errors(function()
        responses["send_" .. status_code_name]()
        assert.stub(ngx.exit).was.called_with(status_code)
      end)
    end
  end)
  it("calls `ngx.log` if 500 or 502 status code was given", function()
    responses.send_HTTP_BAD_REQUEST()
    assert.stub(ngx.log).was_not_called()

    responses.send_HTTP_BAD_REQUEST("error")
    assert.stub(ngx.log).was_not_called()

    responses.send_HTTP_INTERNAL_SERVER_ERROR()
    assert.stub(ngx.log).was_not_called()

    responses.send_HTTP_BAD_GATEWAY()
    assert.stub(ngx.log).was_not_called()

    responses.send_HTTP_INTERNAL_SERVER_ERROR("error")
    assert.stub(ngx.log).was_called()

    responses.send_HTTP_BAD_GATEWAY("error")
    assert.stub(ngx.log).was_called(2)
  end)

  it("don't call `ngx.log` if a 503 status code was given", function()
    responses.send_HTTP_SERVICE_UNAVAILABLE()
    assert.stub(ngx.log).was_not_called()

    responses.send_HTTP_SERVICE_UNAVAILABLE()
    assert.stub(ngx.log).was_not_called("error")
  end)

  describe("default content rules for some status codes", function()
    it("should apply default content rules for some status codes", function()
      responses.send_HTTP_NOT_FOUND()
      assert.stub(ngx.say).was.called_with("{\"message\":\"Not found\"}")
      responses.send_HTTP_NOT_FOUND("override")
      assert.stub(ngx.say).was.called_with("{\"message\":\"override\"}")
    end)
    it("should apply default content rules for some status codes", function()
      responses.send_HTTP_NO_CONTENT("some content")
      assert.is_nil(ngx.header["Content-Type"])
      assert.stub(ngx.say).was.not_called()
    end)
    it("should apply default content rules for some status codes", function()
      responses.send_HTTP_INTERNAL_SERVER_ERROR()
      assert.stub(ngx.say).was.called_with("{\"message\":\"An unexpected error occurred\"}")
      responses.send_HTTP_INTERNAL_SERVER_ERROR("override")
      assert.stub(ngx.say).was.called_with("{\"message\":\"An unexpected error occurred\"}")
    end)
    it("should apply default content rules for some status codes", function()
      responses.send_HTTP_SERVICE_UNAVAILABLE()
      assert.stub(ngx.say).was.called_with("{\"message\":\"Service unavailable\"}")
      responses.send_HTTP_SERVICE_UNAVAILABLE("override")
      assert.stub(ngx.say).was.called_with("{\"message\":\"override\"}")
    end)
  end)

  describe("send()", function()
    it("sends a custom status code", function()
      responses.send(415, "Unsupported media type")
      assert.stub(ngx.say).was.called_with("{\"message\":\"Unsupported media type\"}")
      assert.stub(ngx.exit).was.called_with(415)

      responses.send(415, "Unsupported media type")
      assert.stub(ngx.say).was.called_with("{\"message\":\"Unsupported media type\"}")
      assert.stub(ngx.exit).was.called_with(415)

      responses.send(501)
      assert.stub(ngx.exit).was.called_with(501)
    end)
  end)

  describe("server tokens", function()
    it("are sent by default", function()
      responses.send_HTTP_OK("OK")
      assert.equal(ngx.status, responses.status_codes.HTTP_OK)
      assert.equal(meta._SERVER_TOKENS, ngx.header["Server"])
    end)
    pending("are sent when enabled", function()
      local singletons = require "kong.singletons"
      singletons.configuration = {
        enabled_headers = {
          ["server_tokens"] = true
        },
      }
      responses.send_HTTP_OK("OK")
      assert.equal(ngx.status, responses.status_codes.HTTP_OK)
      assert.equal(meta._SERVER_TOKENS, ngx.header["Server"])
    end)
    it("are not sent when disabled", function()
      local singletons = require "kong.singletons"
      singletons.configuration = {
        enabled_headers = {
        },
      }
      responses.send_HTTP_OK("OK")
      assert.equal(ngx.status, responses.status_codes.HTTP_OK)
      assert.is_nil(ngx.header["Server"])
    end)
  end)

  describe("content-length header", function()
    it("is set", function()
      responses.send_HTTP_OK("OK")
      assert.equal(17, tonumber(ngx.header["Content-Length"]))
    end)

    it("is set to 0 when no content", function()
      responses.send_HTTP_OK()
      assert.equal(0, tonumber(ngx.header["Content-Length"]))
    end)

    it("is set to 0 with HTTP 204", function()
      responses.send_HTTP_NO_CONTENT("this is not sent")
      assert.equal(0, tonumber(ngx.header["Content-Length"]))
    end)
  end)
end)
