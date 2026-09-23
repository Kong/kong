local PLUGIN_NAME = "http-log"


local Queue = require "kong.tools.queue"
local uuid = require "kong.tools.uuid"
local mocker = require "spec.fixtures.mocker"

-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()
  local unmock
  local log_messages

  before_each(function()
    log_messages = ""
    local function log(level, message) -- luacheck: ignore
      log_messages = log_messages .. level .. " " .. message .. "\n"
    end

    mocker.setup(function(f)
      unmock = f
    end, {
      kong = {
        log = {
          debug = function(message) return log('DEBUG', message) end,
          info = function(message) return log('INFO', message) end,
          warn = function(message) return log('WARN', message) end,
          err = function(message) return log('ERR', message) end,
        },
        plugin = {
          get_id = function () return uuid.uuid() end,
        },
      },
      ngx = {
        ctx = {
          -- make sure our workspace is nil to begin with to prevent leakage from
          -- other tests
          workspace = nil
        },
      }
    })
  end)

  after_each(unmock)

  it("accepts minimal config with defaults", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.test/path",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts empty headers with username/password in the http_endpoint", function()
    local ok, err = validate({
        http_endpoint = "http://bob:password@myservice.test/path",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts custom fields by lua", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.test/path",
        custom_fields_by_lua = {
          foo = "return 'bar'",
        }
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("does accept allowed headers", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.test/path",
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
      http_endpoint = "http://myservice.test/path",
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
        http_endpoint = "http://myservice.test/path",
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
        http_endpoint = "http://myservice.test/path",
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
        http_endpoint = "http://myservice.test/path",
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
        http_endpoint = "http://hi:there@myservice.test/path",
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
      http_endpoint = "http://hi:there@myservice.test/path",
      retry_count = 23,
      queue_size = 46,
      flush_timeout = 92,
    })
    assert.is_truthy(entity)
    entity.config.queue.name = "legacy-conversion-test"
    local conf = Queue.get_plugin_params("http-log", entity.config)
    assert.match_re(log_messages, "the retry_count parameter no longer works")
    assert.match_re(log_messages, "the queue_size parameter is deprecated")
    assert.match_re(log_messages, "the flush_timeout parameter is deprecated")
    assert.is_same(46, conf.max_batch_size)
    assert.is_same(92, conf.max_coalescing_delay)
  end)
end)
