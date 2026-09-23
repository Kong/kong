local helpers = require "spec.helpers"
local pl_file = require "pl.file"


local function count_log_lines(pattern)
  local cfg = helpers.test_conf
  local logs = pl_file.read(cfg.prefix .. "/" .. cfg.proxy_error_log)
  local _, count = logs:gsub(pattern, "")
  return count
end


describe("[dns-client] inter-process communication:",function()
  local num_workers = 2

  setup(function()
    local bp = helpers.get_db_utils("postgres", {
      "routes",
      "services",
      "plugins",
    }, {
      "dns-client-test",
    })

    bp.plugins:insert {
      name = "dns-client-test",
    }

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled,dns-client-test",
      nginx_main_worker_processes = num_workers,
      new_dns_client = "on",
    }))
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("stale updating task broadcast events", function()
    helpers.wait_until(function()
      return count_log_lines("DNS query completed") == num_workers
    end, 5)

    assert.same(count_log_lines("first:query:ipc.test"), 1)
    assert.same(count_log_lines("first:answers:1.2.3.4"), num_workers)

    assert.same(count_log_lines("stale:query:ipc.test"), 1)
    assert.same(count_log_lines("stale:answers:1.2.3.4."), num_workers)

    -- wait background tasks to finish
    helpers.wait_until(function()
      return count_log_lines("stale:broadcast:ipc.test:%-1") == 1
    end, 5)

    -- "stale:lru ..." means the progress of the two workers is about the same.
    -- "first:lru ..." means one of the workers is far behind the other.
    helpers.wait_until(function()
      return count_log_lines(":lru delete:ipc.test:%-1") == 1
    end, 5)
  end)
end)
