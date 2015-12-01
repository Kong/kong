local responses = require "kong.tools.responses"
local constants = require "kong.constants"

require "kong.tools.ngx_stub"

describe("Responses", function()

  before_each(function()
    mock(ngx, true) -- mock table with stubs.
  end)

  after_each(function()
    ngx.ctx = {}
    ngx.header = {}
    -- Revert mocked functions
    for _, v in pairs(ngx) do
      if type(v) == "table" and type(v.revert) == "function" then
        v:revert()
      end
    end
  end)

  it("should have a list of the main http status codes used in Kong", function()
    assert.truthy(responses.status_codes)
    assert.are.same("table", type(responses.status_codes))
  end)

  it("should be callable via `send_HTTP_STATUS_CODE`", function()
    for status_code_name, status_code in pairs(responses.status_codes) do
      assert.has_no.errors(function()
        responses["send_"..status_code_name]()
      end)
    end
  end)

  it("should set the correct ngx values and call ngx.say and ngx.exit", function()
    responses.send_HTTP_OK("OK")
    assert.are.same(ngx.status, responses.status_codes.HTTP_OK)
    assert.are.same(ngx.header["Server"], constants.NAME.."/"..constants.VERSION)
    assert.stub(ngx.say).was.called() -- set custom content
    assert.stub(ngx.exit).was.called() -- exit nginx (or continue to the next context if 200)
  end)

  it("should send the content as a JSON string with a `message` property if given a string", function()
    responses.send_HTTP_OK("OK")
    assert.stub(ngx.say).was.called_with("{\"message\":\"OK\"}")
  end)

  it("should send the content as a JSON string if given a table", function()
    responses.send_HTTP_OK({ success = true })
    assert.stub(ngx.say).was.called_with("{\"success\":true}")
  end)

  it("should send the content as passed if `raw` is given", function()
    responses.send_HTTP_OK("OK", true)
    assert.stub(ngx.say).was.called_with("OK")
  end)

  it("should call `ngx.exit` with the corresponding status_code", function()
    for status_code_name, status_code in pairs(responses.status_codes) do
      assert.has_no.errors(function()
        responses["send_"..status_code_name]()
        assert.stub(ngx.exit).was.called_with(status_code)
      end)
    end
  end)

  it("should call `ngx.log` if and only if a 500 status code range was given", function()
    responses.send_HTTP_BAD_REQUEST()
    assert.stub(ngx.log).was_not_called()

    responses.send_HTTP_INTERNAL_SERVER_ERROR()
    assert.stub(ngx.log).was_not_called()

    responses.send_HTTP_INTERNAL_SERVER_ERROR("error")
    assert.stub(ngx.log).was_called()
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
      assert.stub(ngx.say).was.not_called()
    end)

    it("should apply default content rules for some status codes", function()
      responses.send_HTTP_INTERNAL_SERVER_ERROR()
      assert.stub(ngx.say).was.called_with("{\"message\":\"An unexpected error occurred\"}")
      responses.send_HTTP_INTERNAL_SERVER_ERROR("override")
      assert.stub(ngx.say).was.called_with("{\"message\":\"An unexpected error occurred\"}")
    end)

  end)

  describe("#send()", function()

    it("should send a custom status code", function()
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
end)
