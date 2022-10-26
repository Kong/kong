local wrpc_queue = require "kong.tools.wrpc.queue"
local semaphore = require "ngx.semaphore"

describe("kong.tools.wrpc.queue", function()
  local queue

  before_each(function()
    queue = wrpc_queue.new()
  end)

  it("simple", function()
    assert.same({ nil, "timeout" }, { queue:pop(0) })
    queue:push("test0")
    queue:push("test1")
    queue:push("test2")
    assert.same("test0", queue:pop())
    assert.same("test1", queue:pop())
    assert.same("test2", queue:pop(0.5))
    assert.same({ nil, "timeout" }, { queue:pop(0) })
  end)

  it("simple2", function()
    queue:push("test0")
    queue:push("test1")
    assert.same("test0", queue:pop())
    queue:push("test2")
    assert.same("test1", queue:pop())
    assert.same("test2", queue:pop())
    assert.same({ nil, "timeout" }, { queue:pop(0) })
  end)

  it("thread", function()
    local smph = semaphore.new()
    ngx.thread.spawn(function()
      -- wait for no time so it will timed out
      assert.same({ nil, "timeout" }, { queue:pop(0) })
      assert.same({}, queue:pop())
      assert.same({1}, queue:pop())
      assert.same({2}, queue:pop())
      assert.same({ nil, "timeout" }, { queue:pop(0) })
      smph:post()
    end)
    -- yield
    ngx.sleep(0)
    queue:push({})
    queue:push({1})
    queue:push({2})
    -- yield to allow thread to finish
    ngx.sleep(0)

    -- should be empty again
    assert.same({ nil, "timeout" }, { queue:pop(0) })
    queue:push({2, {}})
    assert.same({2, {}}, queue:pop())

    assert(smph:wait(0), "thread is not resumed")
  end)
end)
