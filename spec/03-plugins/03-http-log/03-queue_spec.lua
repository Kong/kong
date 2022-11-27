local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: http-log (queue) [#" .. strategy .. "]", function()
    it("Queue id serialization", function()
      local get_queue_id = require("kong.plugins.http-log.handler").__get_queue_id
      local conf = {
        http_endpoint = "http://example.com",
        method = "POST",
        content_type = "application/json",
        timeout = 1000,
        keepalive = 1000,
        retry_count = 10,
        queue_size = 100,
        flush_timeout = 1000,
      }

      local queue_id = get_queue_id(conf)
      assert.equal("http://example.com:POST:application/json:1000:1000:10:100:1000", queue_id)
    end)
  end)
end
