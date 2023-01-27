local PLUGIN_NAME = "http-log"


local helpers = require "spec.helpers"
local Queue = require "kong.tools.queue"


-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()
  local old_log
  local log_messages

  before_each(function()
    old_log = ngx.log
    log_messages = ""
    ngx.log = function(level, message) -- luacheck: ignore
      log_messages = log_messages .. helpers.ngx_log_level_names[level] .. " " .. message .. "\n"
    end
  end)

  after_each(function()
    ngx.log = old_log -- luacheck: ignore
  end)

  it("accepts minimal config with defaults", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.com/path",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts empty headers with username/password in the http_endpoint", function()
    local ok, err = validate({
        http_endpoint = "http://bob:password@myservice.com/path",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts custom fields by lua", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.com/path",
        custom_fields_by_lua = {
          foo = "return 'bar'",
        }
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("does accept allowed headers", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.com/path",
        headers = {
          ["X-My-Header"] = "123",
          ["X-Your-Header"] = "abc",
        }
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("does not accept empty header values", function()
    local ok, err = validate({
      http_endpoint = "http://myservice.com/path",
      headers = {
        ["X-My-Header"] = "",
      }
    })
    assert.same({
      config = {
        headers = "length must be at least 1"
      } }, err)
    assert.is_falsy(ok)
  end)

  it("does not accept Host header", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.com/path",
        headers = {
          ["X-My-Header"] = "123",
          Host = "MyHost",
        }
      })
      assert.same({
        config = {
          headers = "cannot contain 'Host' header"
        } }, err)
      assert.is_falsy(ok)
    end)


  it("does not accept Content-Length header", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.com/path",
        headers = {
          ["coNTEnt-Length"] = "123",  -- also validate casing
        }
      })
    assert.same({
      config = {
        headers = "cannot contain 'Content-Length' header"
      } }, err)
    assert.is_falsy(ok)
  end)


  it("does not accept Content-Type header", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.com/path",
        headers = {
          ["coNTEnt-Type"] = "bad"  -- also validate casing
        }
      })
    assert.same({
      config = {
        headers = "cannot contain 'Content-Type' header"
      } }, err)
    assert.is_falsy(ok)
  end)


  it("does not accept userinfo in URL and 'Authorization' header", function()
    local ok, err = validate({
        http_endpoint = "http://hi:there@myservice.com/path",
        headers = {
          ["AuthoRIZATion"] = "bad"  -- also validate casing
        }
      })
    assert.same({
        config = "specifying both an 'Authorization' header and user info in 'http_endpoint' is not allowed"
      }, err)
    assert.is_falsy(ok)
  end)

  it("converts legacy queue parameters", function()
    local entity = validate({
      http_endpoint = "http://hi:there@myservice.com/path",
      retry_count = 23,
      queue_size = 46,
      flush_timeout = 92,
    })
    assert.is_truthy(entity)
    local conf = Queue.get_params(entity.config)
    assert.match_re(log_messages, "deprecated `retry_count`")
    assert.match_re(log_messages, "deprecated `queue_size`")
    assert.match_re(log_messages, "deprecated `flush_timeout`")
    assert.is_same(46, conf.batch_max_size)
    assert.is_same(92, conf.max_delay)
  end)
end)
