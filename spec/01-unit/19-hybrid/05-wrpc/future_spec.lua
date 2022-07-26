local semaphore = require "ngx.semaphore"
local match = require "luassert.match"
local helpers = require "spec.helpers"
local semaphore_new = semaphore.new


describe("kong.tools.wrpc.future", function()
  local wrpc_future
  local log_spy = spy.new()
  local ngx_log = ngx.log
  lazy_setup(function()
    ngx.log = log_spy -- luacheck: ignore
    package.loaded["kong.tools.wrpc.future"] = nil
    wrpc_future = require "kong.tools.wrpc.future"
  end)
  lazy_teardown(function()
    ngx.log = ngx_log -- luacheck: ignore
  end)

  local fake_peer
  before_each(function()
    fake_peer = {
      responses = {},
      seq = 1,
    }
  end)

  it("then_do", function()
    local smph1 = semaphore_new()
    local smph2 = semaphore_new()

    local future1 = wrpc_future.new(fake_peer, 1)
    fake_peer.seq = fake_peer.seq + 1
    local future2 = wrpc_future.new(fake_peer, 1)
    assert.same(2, #fake_peer.responses)

    future1:then_do(function(data)
      assert.same("test1", data)
      smph1:post()
    end)
    future2:then_do(function(data)
      assert.same("test2", data)
      smph2:post()
    end)

    future2:done("test2")
    future1:done("test1")


    assert(smph1:wait(1))
    assert(smph2:wait(1))


    future2:then_do(function(_)
      assert.fail("future2 should not recieve data")
    end, function()
      smph2:post()
    end)

    assert(smph2:wait(5))
    assert.is_same({}, fake_peer.responses)
  end)

  it("wait", function()
    local smph = semaphore_new()

    local future1 = wrpc_future.new(fake_peer, 1)
    fake_peer.seq = fake_peer.seq + 1
    local future2 = wrpc_future.new(fake_peer, 1)
    fake_peer.seq = fake_peer.seq + 1
    local future3 = wrpc_future.new(fake_peer, 1)
    assert.same(3, #fake_peer.responses)

    ngx.thread.spawn(function()
      assert.same({ 1 }, future1:wait())
      assert.same({ 2 }, future2:wait())
      assert.same({ 3 }, future3:wait())
      assert.same({ nil, "timeout" }, { future3:wait() })
      smph:post()
    end)

    future2:done({ 2 })
    future1:done({ 1 })
    future3:done({ 3 })


    assert(smph:wait(5))
    assert.is_same({}, fake_peer.responses)
  end)

  it("drop", function()
    local smph = semaphore_new()

    local future1 = wrpc_future.new(fake_peer, 1)
    fake_peer.seq = fake_peer.seq + 1
    local future2 = wrpc_future.new(fake_peer, 1)
    fake_peer.seq = fake_peer.seq + 1
    local future3 = wrpc_future.new(fake_peer, 1)
    assert.same(3, #fake_peer.responses)

    ngx.thread.spawn(function()
      assert(future1:drop())
      assert(future2:drop())
      assert(future3:drop())
      smph:post()
    end)

    future2:done({ 2 })
    future1:done({ 1 })
    future3:done({ 3 })

    assert(smph:wait(1))
    assert.spy(log_spy).was_not_called_with(ngx.ERR, match._, match._)
    assert.is_same({}, fake_peer.responses)

    ngx.thread.spawn(function()
      assert(future1:drop())
      assert(future2:drop())
      assert(future3:drop())
      smph:post()
    end)

    future2:done({ 2 })
    future1:done({ 1 })

    smph:wait(1)
    helpers.wait_until(function()
      return pcall(assert.spy(log_spy).was_called_with, ngx.ERR, match._, match._)
    end, 5)
  end)
end)
