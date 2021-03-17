local subject = require('kong.plugins.file-log.attribute_remover')

describe("Plugin: file-log (attribute_remover)", function()
  it("removes the attributes specified at the censored_fields array from the log message", function()
    local log = {
      request = {
        url = 'https://some-awesome-url.com/kong/rocks',
        headers = {
          ["x-kong-header"] = 'another-cool-header',
          ["x-kong-api-key"] = 'some-api-key',
        }
      }
    }
    local censored_fields = {'request.headers.x-kong-api-key'}
    local censored_message = subject.delete_attributes(log, censored_fields)
    local expected = {
      request = {
        url = 'https://some-awesome-url.com/kong/rocks',
        headers = {
          ["x-kong-header"] = 'another-cool-header',
        }
      }
    }
    assert.are.same(censored_message, expected)
  end)

  it("does not remove attributes from the log message when no attributes were specified", function()
    local log = {
      request = {
        url = 'https://some-awesome-url.com/kong/rocks',
        headers = {
          ["x-kong-header"] = 'another-cool-header',
          ["x-kong-api-key"] = 'some-api-key',
        }
      }
    }
    local censored_fields = {}
    local censored_message = subject.delete_attributes(log, censored_fields)
    assert.are.same(log, censored_message)
  end)
end)
