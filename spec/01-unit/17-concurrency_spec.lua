local mocker = require("spec.fixtures.mocker")


-- avoid requiring spec.helpers to avoid complicating necessary mocks
local function unindent(s)
  return s:gsub("\n%s*", "\n"):gsub("^%s*", ""):gsub("\n$", "")
end


local function setup_it_block()

  -- keep track of created semaphores
  local semaphores = {}

  mocker.setup(finally, {

    ngx = {
      log = function()
        -- avoid stdout output during test
      end,
    },

    kong = {
      log = {
        err = function() end,
        warn = function() end,
      },
      response = {
        exit = function() end,
      },
    },

    modules = {
      { "ngx.semaphore",  {
        _semaphores = semaphores,
        new = function()
          local s = {
            value = 0,
            wait = function(self, timeout)
              local t = 0
              while self.value == 0 do
                coroutine.yield()
                t = t + 1
                if t == timeout then
                  return nil, "timeout"
                end
              end
              self.value = self.value - 1
              return true
            end,
            post = function(self, n)
              n = n or 1
              self.value = self.value + n
              return true
            end,
          }
          table.insert(semaphores, s)
          return s
        end,
      }},

      { "kong.concurrency", {} },
    }

  })
end

describe("kong.concurrency", function()
  describe("with_coroutine_mutex", function()

    it("baseline demo without locking", function()
      setup_it_block()

      local output = {}

      local co = {}
      for c = 1, 2 do
        co[c] = coroutine.create(function()
          table.insert(output, "hello " .. c)
          coroutine.yield()

          table.insert(output, "inside " .. c)
          coroutine.yield()
          table.insert(output, "releasing " .. c)

          table.insert(output, "goodbye " .. c)
        end)
      end

      -- mock a round-robin coroutine scheduler
      for i = 1, 10 do
        coroutine.resume(co[1])
        coroutine.resume(co[2])
      end

      assert.same(unindent([[
        hello 1
        hello 2
        inside 1
        inside 2
        releasing 1
        goodbye 1
        releasing 2
        goodbye 2
      ]]), table.concat(output, "\n"))
    end)

    it("locks coroutines with a mutex", function()
      setup_it_block()

      local output = {}

      local co = {}
      for c = 1, 2 do
        co[c] = coroutine.create(function()
          local concurrency = require("kong.concurrency")
          table.insert(output, "hello " .. c)
          coroutine.yield()
          concurrency.with_coroutine_mutex({ name = "test" }, function()
            table.insert(output, "inside " .. c)
            coroutine.yield()
            table.insert(output, "releasing " .. c)
          end)
          table.insert(output, "goodbye " .. c)
        end)
      end

      -- mock a round-robin coroutine scheduler
      for i = 1, 10 do
        coroutine.resume(co[1])
        coroutine.resume(co[2])
      end

      assert.same(unindent([[
        hello 1
        hello 2
        inside 1
        releasing 1
        goodbye 1
        inside 2
        releasing 2
        goodbye 2
      ]]), table.concat(output, "\n"))
    end)

    it("has option on_timeout = 'run_unlocked'", function()
      setup_it_block()

      local output = {}

      local co = {}
      for c = 1, 2 do
        co[c] = coroutine.create(function()
          local concurrency = require("kong.concurrency")
          table.insert(output, "hello " .. c)
          coroutine.yield()
          local opts = {
            name = "test",
            timeout = 5,
            on_timeout = "run_unlocked",
          }
          concurrency.with_coroutine_mutex(opts, function()
            for i = 1, 10 do
              table.insert(output, "taking a while (" .. i .. ") " .. c)
              coroutine.yield()
            end
            table.insert(output, "releasing " .. c)
          end)
          table.insert(output, "goodbye " .. c)
        end)
      end

      -- mock a round-robin coroutine scheduler
      for i = 1, 20 do
        coroutine.resume(co[1])
        coroutine.resume(co[2])
      end

      assert.same(unindent([[
        hello 1
        hello 2
        taking a while (1) 1
        taking a while (2) 1
        taking a while (3) 1
        taking a while (4) 1
        taking a while (5) 1
        taking a while (6) 1
        taking a while (1) 2
        taking a while (7) 1
        taking a while (2) 2
        taking a while (8) 1
        taking a while (3) 2
        taking a while (9) 1
        taking a while (4) 2
        taking a while (10) 1
        taking a while (5) 2
        releasing 1
        goodbye 1
        taking a while (6) 2
        taking a while (7) 2
        taking a while (8) 2
        taking a while (9) 2
        taking a while (10) 2
        releasing 2
        goodbye 2
      ]]), table.concat(output, "\n"))
    end)

    it("has option on_timeout = 'return_true'", function()
      setup_it_block()

      local output = {}

      local co = {}
      for c = 1, 2 do
        co[c] = coroutine.create(function()
          local concurrency = require("kong.concurrency")
          table.insert(output, "hello " .. c)
          coroutine.yield()
          local opts = {
            name = "test",
            timeout = 5,
            on_timeout = "return_true",
          }
          local ok, err = concurrency.with_coroutine_mutex(opts, function()
            for i = 1, 10 do
              table.insert(output, "taking a while (" .. i .. ") " .. c)
              coroutine.yield()
            end
            table.insert(output, "releasing " .. c)
          end)
          if c == 2 then
            assert.truthy(ok)
            assert.is_nil(err)
          end
          table.insert(output, "goodbye " .. c)
        end)
      end

      -- mock a round-robin coroutine scheduler
      for i = 1, 20 do
        coroutine.resume(co[1])
        coroutine.resume(co[2])
      end

      assert.same(unindent([[
        hello 1
        hello 2
        taking a while (1) 1
        taking a while (2) 1
        taking a while (3) 1
        taking a while (4) 1
        taking a while (5) 1
        taking a while (6) 1
        goodbye 2
        taking a while (7) 1
        taking a while (8) 1
        taking a while (9) 1
        taking a while (10) 1
        releasing 1
        goodbye 1
      ]]), table.concat(output, "\n"))
    end)

    it("supports multiple locks", function()
      setup_it_block()

      local output = {}

      local co = {}
      -- coroutines 1 and 2 share a lock
      for c = 1, 2 do
        co[c] = coroutine.create(function()
          local concurrency = require("kong.concurrency")
          table.insert(output, "hello " .. c)
          coroutine.yield()
          concurrency.with_coroutine_mutex({ name = "test1" }, function()
            table.insert(output, "inside " .. c)
            coroutine.yield()
            table.insert(output, "releasing " .. c)
          end)
          table.insert(output, "goodbye " .. c)
        end)
      end

      -- coroutines 3 and 4 share a different lock
      for c = 3, 4 do
        co[c] = coroutine.create(function()
          local concurrency = require("kong.concurrency")
          table.insert(output, "hello " .. c)
          coroutine.yield()
          concurrency.with_coroutine_mutex({ name = "test2" }, function()
            table.insert(output, "inside " .. c)
            coroutine.yield()
            table.insert(output, "releasing " .. c)
          end)
          table.insert(output, "goodbye " .. c)
        end)
      end

      -- mock a round-robin coroutine scheduler
      for i = 1, 10 do
        coroutine.resume(co[1])
        coroutine.resume(co[2])
        coroutine.resume(co[3])
        coroutine.resume(co[4])
      end

      assert.same(unindent([[
        hello 1
        hello 2
        hello 3
        hello 4
        inside 1
        inside 3
        releasing 1
        goodbye 1
        inside 2
        releasing 3
        goodbye 3
        inside 4
        releasing 2
        goodbye 2
        releasing 4
        goodbye 4
      ]]), table.concat(output, "\n"))
    end)
  end)
end)

