require "kong.tools.utils"


describe("Observability/Logs unit tests", function()
  describe("maybe_push()", function()
    local o11y_logs, maybe_push, get_request_logs, get_worker_logs
    local old_ngx, old_kong

    lazy_setup(function()
      old_ngx = _G.ngx
      old_kong = _G.kong

      _G.ngx = {
        config = { subsystem = "http" },
        ctx = {},
        DEBUG = ngx.DEBUG,
        INFO = ngx.INFO,
        WARN = ngx.WARN,
      }

      _G.kong = {
        configuration = {
          log_level = "info",
        },
      }

      o11y_logs = require "kong.observability.logs"
      maybe_push = o11y_logs.maybe_push
      get_request_logs = o11y_logs.get_request_logs
      get_worker_logs = o11y_logs.get_worker_logs
    end)

    before_each(function()
      _G.ngx.ctx = {}
    end)

    lazy_teardown(function()
      _G.ngx = old_ngx
      _G.kong = old_kong
    end)

    it("has no effect when log level is lower than the configured value", function()
      maybe_push(1, nil, ngx.DEBUG, "Don't mind me, I'm just a debug log")
      local worker_logs = get_worker_logs()
      assert.same({}, worker_logs)
      local request_logs = get_request_logs()
      assert.same({}, request_logs)
    end)

    it("considers log message as optional", function()
      local log_level = ngx.INFO

      maybe_push(1, nil, log_level)
      local worker_logs = get_worker_logs()
      assert.equals(1, #worker_logs)

      local logged_entry = worker_logs[1]
      assert.same(log_level, logged_entry.log_level)
      assert.equals("", logged_entry.body)
      assert.is_table(logged_entry.attributes)
      assert.is_number(logged_entry.observed_time_unix_nano)
      assert.is_number(logged_entry.time_unix_nano)
      assert.is_number(logged_entry.attributes["introspection.current.line"])
      assert.is_string(logged_entry.attributes["introspection.name"])
      assert.is_string(logged_entry.attributes["introspection.namewhat"])
      assert.is_string(logged_entry.attributes["introspection.source"])
      assert.is_string(logged_entry.attributes["introspection.what"])
    end)

    it("generates worker-scoped log entries", function()
      local log_level = ngx.WARN
      local body = "Careful! I'm a warning!"

      maybe_push(1, { foo = "bar", tst = "baz" }, log_level, body, true, 123, ngx.null, nil, function()end, { foo = "bar" })
      local worker_logs = get_worker_logs()
      assert.equals(1, #worker_logs)

      local logged_entry = worker_logs[1]
      assert.same(log_level, logged_entry.log_level)
      assert.matches(body .. "true123nilnilfunction:%s0x%x+table:%s0x%x+", logged_entry.body)
      assert.is_table(logged_entry.attributes)
      assert.is_number(logged_entry.attributes["introspection.current.line"])
      assert.is_string(logged_entry.attributes["introspection.name"])
      assert.is_string(logged_entry.attributes["introspection.namewhat"])
      assert.is_string(logged_entry.attributes["introspection.source"])
      assert.is_string(logged_entry.attributes["introspection.what"])
      assert.equals("bar", logged_entry.attributes.foo)
      assert.equals("baz", logged_entry.attributes.tst)
      assert.is_number(logged_entry.observed_time_unix_nano)
      assert.is_number(logged_entry.time_unix_nano)
    end)
  end)
end)
