local helpers = require "spec.helpers"
local cjson = require "cjson"

-- We already test the functionality of page() when filtering by tag in
-- spec/02-integration/03-db/07-tags_spec.lua.
-- This test we test on the correctness of the admin API response so that
-- we can ensure the right function (page()) is executed.
describe("Admin API - tags", function()
  for _, strategy in helpers.each_strategy() do
    describe("/entities?tags= with DB: #" .. strategy, function()
      local client, bp

      lazy_setup(function()
        bp = helpers.get_db_utils(strategy, {
          "consumers",
          "plugins",
        })

        for i = 1, 2 do
          local consumer = {
            username = "adminapi-filter-by-tag-" .. i,
            tags = { "corp_ a", "consumer_ "..i, "🦍" }
          }
          local row, err, err_t = bp.consumers:insert(consumer)
          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.same(consumer.tags, row.tags)

          bp.plugins:insert({
            name = "file-log",
            consumer = { id = row.id },
            config = {
              path = os.tmpname(),
            },
            tags = { "corp_ a", "consumer_ " .. i }
          })
        end

        assert(helpers.start_kong {
          database = strategy,
        })
        client = assert(helpers.admin_client(10000))
      end)

      lazy_teardown(function()
        if client then client:close() end
        helpers.stop_kong()
      end)

      it("filter by single tag", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers?tags=corp_%20a"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(2, #json.data)
        for i = 1, 2 do
          assert.contains('corp_ a', json.data[i].tags)
        end
      end)

      it("filter by single unicode tag", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers?tags=🦍"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(2, #json.data)
        for i = 1, 2 do
          assert.contains("🦍", json.data[i].tags)
        end
      end)

      it("filter by multiple tags with AND", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers?tags=corp_%20a,consumer_%201"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(1, #json.data)
        assert.equals(3, #json.data[1].tags)
        assert.contains('corp_ a', json.data[1].tags)
        assert.contains('consumer_ 1', json.data[1].tags)
        assert.contains('🦍', json.data[1].tags)
      end)

      it("filter by multiple tags with OR", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers?tags=consumer_%202/consumer_%201"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(2, #json.data)
      end)

      it("ignores tags when filtering by multiple filters #6779", function()
        local res = client:get("/consumers/adminapi-filter-by-tag-1/plugins?tags=consumer_%202")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(1, #json.data)

        assert.contains('corp_ a', json.data[1].tags)
        assert.contains('consumer_ 1', json.data[1].tags)
        assert.not_contains('consumer_ 2', json.data[1].tags)
      end)

      it("errors if filter by mix of AND and OR", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers?tags=consumer_%203,consumer_%202/consumer_%201"
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equals("invalid option (tags: invalid filter syntax)", json.message)

        local res = assert(client:send {
          method = "GET",
          path = "/consumers?tags=consumer_%203/consumer_%202,consumer_%201"
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equals("invalid option (tags: invalid filter syntax)", json.message)
      end)

      it("errors if filter by tag with invalid value", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers?tags=" .. string.char(255)
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equals("invalid option (tags: invalid filter syntax)", json.message)
      end)

      it("returns the correct 'next' arg", function()
        local tags_arg = 'tags=corp_%20a'
        local res = assert(client:send {
          method = "GET",
          path = "/consumers?" .. tags_arg .. "&size=1"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(1, #json.data)
        assert.match(tags_arg, json.next, 1, true)
      end)

    end)

    describe("/tags with DB: #" .. strategy, function()
      local client, bp

      lazy_setup(function()
        bp = helpers.get_db_utils(strategy, {
          "consumers",
        })

        for i = 1, 2 do
          local consumer = {
            username = "adminapi-filter-by-tag-" .. i,
            tags = { "corp_ a",  "consumer_ "..i }
          }
          local row, err, err_t = bp.consumers:insert(consumer)
          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.same(consumer.tags, row.tags)
        end

        assert(helpers.start_kong {
          database = strategy,
        })
        client = assert(helpers.admin_client(10000))
      end)

      lazy_teardown(function()
        if client then client:close() end
        helpers.stop_kong()
      end)

      it("/tags", function()
        local res = assert(client:send {
          method = "GET",
          path = "/tags"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(4, #json.data)
      end)

      it("/tags/:tags", function()
        local res = assert(client:send {
          method = "GET",
          path = "/tags/corp_%20a"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(2, #json.data)
      end)

      it("/tags/:tags with a not exist tag", function()
        local res = assert(client:send {
          method = "GET",
          path = "/tags/does-not-exist"
        })
        local body = assert.res_status(200, res)
        local ok = string.find(body, '"data":[]', nil, true)
        assert.truthy(ok)
      end)

      it("/tags/:tags with invalid :tags value", function()
        local res = assert(client:send {
          method = "GET",
          path = "/tags/" .. string.char(255)
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.matches("invalid utf%-8", json.message)
      end)

      it("/tags ignores ?tags= query", function()
        local res = assert(client:send {
          method = "GET",
          path = "/tags?tags=not_a_tag"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(4, #json.data)

        local res = assert(client:send {
          method = "GET",
          path = "/tags?tags=invalid@tag"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(4, #json.data)
      end)

      it("/tags/:tags ignores ?tags= query", function()
        local res = assert(client:send {
          method = "GET",
          path = "/tags/corp_%20a?tags=not_a_tag"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(2, #json.data)

        local res = assert(client:send {
          method = "GET",
          path = "/tags/corp_%20a?tags=invalid@tag"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(2, #json.data)
      end)
    end)
  end
end)
