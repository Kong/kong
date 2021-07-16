-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("jq-filter request (" .. strategy .. ")", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services", "plugins",
      }, { "jq-filter" })

      do
        local route1 = bp.routes:insert({
          hosts = { "test1.example.com" },
        })
        local route2 = bp.routes:insert({
          hosts = { "test2.example.com" },
        })
        local route3 = bp.routes:insert({
          hosts = { "test3.example.com" },
        })

        -- returns the first element in the request body
        bp.plugins:insert({
          route     = { id = route1.id },
          name      = "jq-filter",
          config    = {
            filters = {
              {
                context = "request",
                target = "body",
                program = ".[1]",
              },
            },
          },
        })

        -- returns value of "foo" in the request body as a raw string
        bp.plugins:insert({
          route     = { id = route2.id },
          name      = "jq-filter",
          config    = {
            filters = {
              {
                context = "request",
                target = "body",
                program = ".foo",
                jq_options = {
                  raw_output = true,
                }
              },
            },
          },
        })

        -- returns value of "foo" in the request body as a raw string
        bp.plugins:insert({
          route     = { id = route3.id },
          name      = "jq-filter",
          config    = {
            filters = {
              {
                context = "request",
                target = "body",
                program = ".foo",
                jq_options = {
                  join_output = true,
                }
              },
            },
          },
        })
      end

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "jq-filter"
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("body", function()
      it("filters with default options", function()
        local r = assert(client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"] = "test1.example.com",
            ["Content-Type"] = "application/json",
          },
          body = {
            { foo = "bar" },
            { bar = "foo" },
          },
        })
        local json = assert.request(r).has.jsonbody()
        assert.same({ bar = "foo" }, json.params)
      end)

      it("returns null when filter is out of range", function()
        local r = assert(client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"] = "test1.example.com",
            ["Content-Type"] = "application/json",
          },
          body = {
            { foo = "bar" },
          },
        })
        local json = assert.request(r).has.jsonbody()
        assert.same(ngx.null, json.params)
      end)

      it("returns null when filter is out of range", function()
        local r = assert(client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"] = "test1.example.com",
            ["Content-Type"] = "application/json",
          },
          body = {
            { foo = "bar" },
          },
        })
        local json = assert.request(r).has.jsonbody()
        assert.same(ngx.null, json.params)
      end)

      it("filters with raw_output", function()
        local r = assert(client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"] = "test2.example.com",
            ["Content-Type"] = "application/json",
          },
          body = {
            foo = "bar",
          },
        })
        local json = assert.request(r).has.jsonbody()
        assert.same("bar\n", json.data)
      end)

      it("filters with join_output", function()
        local r = assert(client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"] = "test3.example.com",
            ["Content-Type"] = "application/json",
          },
          body = {
            foo = "bar",
          },
        })
        local json = assert.request(r).has.jsonbody()
        assert.same("bar", json.data)
      end)
    end)
  end)
end
