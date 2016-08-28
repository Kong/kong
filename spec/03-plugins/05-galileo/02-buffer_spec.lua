local Buffer

local function reload_buffer()
  package.loaded["spec.03-plugins.05-galileo.ngx"] = nil
  package.loaded["kong.plugins.galileo.buffer"] = nil

  _G.ngx = require "spec.03-plugins.05-galileo.ngx"
  Buffer = require "kong.plugins.galileo.buffer"
end

describe("ALF Buffer", function()
  local conf, _ngx
  before_each(function()
    reload_buffer()

    conf = {
      server_addr = "10.10.10.10",
      service_token = "abcd",
      environment = "test",
      log_bodies = false,
      retry_count = 0,
      connection_timeout = 30,
      flush_timeout = 2,
      queue_size = 1000,
      host = "collector.galileo.mashape.com",
      port = 443
    }

    _ngx = {
      status = 200,
      var = {
        scheme = "https",
        host = "mockbin.com",
        request_uri = "/request/path",
        request_length = 32,
        remote_addr = "127.0.0.1",
        server_addr = "10.10.10.10"
      },
      ctx = {
        KONG_PROXY_LATENCY = 3,
        KONG_WAITING_TIME = 15,
        KONG_RECEIVE_TIME = 25
      }
    }
  end)

  it("sanity", function()
    local buf = assert(Buffer.new(conf))
    assert.equal(0, #buf.sending_queue)
    assert.equal(0, #buf.cur_alf.entries)
    assert.equal(conf.flush_timeout * 1000, buf.flush_timeout)
    assert.equal(conf.connection_timeout * 1000, buf.connection_timeout)
  end)
  it("sane defaults", function()
    local buf = assert(Buffer.new {
      service_token = "abcd",
      server_addr = "",
      host = "",
      port = 80
    })
    assert.equal(0, buf.retry_count)
    assert.equal(30000, buf.connection_timeout)
    assert.equal(2000, buf.flush_timeout)
    assert.equal(1000, buf.queue_size)
    assert.False(buf.log_bodies)
  end)
  it("returns error on invalid conf", function()
    local buf, err = Buffer.new()
    assert.equal("arg #1 (conf) must be a table", err)
    assert.is_nil(buf)
    buf, err = Buffer.new {}
    assert.equal("server_addr must be a string", err)
    assert.is_nil(buf)
    buf, err = Buffer.new {server_addr = "10.10.10.10"}
    assert.equal("service_token must be a string", err)
    assert.is_nil(buf)
    buf, err = Buffer.new {
      service_token = "abcd",
      server_addr = "10.10.10.10",
      environment = false
    }
    assert.equal("environment must be a string", err)
    assert.is_nil(buf)
  end)

  describe("add_entry()", function()
    it("adds an entry to the underlying ALF serializer", function()
      local buf = assert(Buffer.new(conf))
      assert.equal(0, #buf.cur_alf.entries)
      for i = 1, 10 do
        assert(buf:add_entry(_ngx, nil, nil))
        assert.equal(i, #buf.cur_alf.entries)
      end
    end)
    it("calls flush() if the number of entries reaches 'queue_size'", function()
      local buf = assert(Buffer.new(conf))
      local s_flush = spy.on(buf, "flush")

      assert.equal(0, #buf.cur_alf.entries)
      for i = 1, conf.queue_size - 1 do
        assert(buf:add_entry(_ngx, nil, nil))
      end

      assert.equal(conf.queue_size - 1, #buf.cur_alf.entries)
      assert(buf:add_entry(_ngx, nil, nil))
      assert.spy(s_flush).was_called(1)
    end)
    it("refreshes last_t on each call", function()
      local buf = assert(Buffer.new(conf))
      local last_t = buf.last_t
      assert(buf:add_entry(_ngx, nil, nil))
      assert.is_number(buf.last_t)
      assert.not_equal(last_t, buf.last_t)
    end)
  end)

  describe("flush()", function()
    it("JSON encode the current ALF and add it to sending_queue", function()
      local buf = assert(Buffer.new(conf))
      local send = stub(buf, "send")

      assert.equal(0, #buf.cur_alf.entries)
      for i = 1, 20 do
        assert(buf:add_entry(_ngx, nil, nil))
      end
      assert(buf:flush())
      assert.stub(send).was_called(1)
      assert.equal(0, #buf.cur_alf.entries) -- flushed
      assert.equal(1, #buf.sending_queue)
      assert.True(buf.sending_queue_size > 0)

      for i = 1, 20 do
        assert(buf:add_entry(_ngx, nil, nil))
      end
      assert(buf:flush())
      assert.stub(send).was_called(2)
      assert.equal(0, #buf.cur_alf.entries) -- flushed
      assert.equal(2, #buf.sending_queue)
    end)
    it("discards ALFs when we have too much data in 'sending_queue' already",function()
      conf.log_bodies = true
      local body_10mb = string.rep(".", 10 * 2^20)
      local buf = assert(Buffer.new(conf))

      assert.has_error(function()
        for i = 1, 210 do -- exceeding our 200MB limit
          assert(buf:add_entry(_ngx, body_10mb))
          local ok, err = buf:flush() -- growing the sending_queue, as if it's stuck
          if not ok then
            error(err) -- assert() seems to not work with assert.has_error
          end
        end
      end, "buffer full")
    end)
  end)

  describe("send()", function()
    it("returns if the 'sending_queue' is empty", function()
      local buf = assert(Buffer.new(conf))
      local ok, err = buf:send()
      assert.equal("empty queue", err)
      assert.is_nil(ok)
    end)
    it("pops the oldest batch in the 'sending_queue'", function()
      conf.log_bodies = true
      local buf = assert(Buffer.new(conf))
      assert(buf:add_entry(_ngx, "body1"))

      assert(buf:flush()) -- calling send()
      assert.equal(0, #buf.sending_queue) -- poped
    end)
  end)
end)
