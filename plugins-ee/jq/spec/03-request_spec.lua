-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.all_strategies() do

describe("jq request #" .. strategy, function()
  local client

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, {
      "routes",
      "services", "plugins",
    }, { "jq" })

    do
      local routes = {}
      for i = 1, 9 do
        table.insert(routes,
                      bp.routes:insert({
                        hosts = { "test" .. i .. ".example.com" }
                      }))
      end

      local function add_plugin(route, config)
        bp.plugins:insert({
          route = { id = route.id },
          name = "jq",
          config = config,
        })
      end

      -- returns the second element in the request body
      add_plugin(routes[1], {
        request_jq_program = ".[1]",
      })

      -- returns value of "foo" in the request body as a raw string
      add_plugin(routes[2], {
        request_jq_program = ".foo",
        request_jq_program_options = {
          raw_output = true,
        }
      })

      -- returns value of "foo" in the request body as a raw string
      add_plugin(routes[3], {
        request_jq_program = ".foo",
        request_jq_program_options = {
          join_output = true,
        }
      })

      -- returns ascii escaped value of "foo" in the request body
      add_plugin(routes[4], {
        request_jq_program = ".foo",
        request_jq_program_options = {
          ascii_output = true,
        }
      })

      -- sorts keys
      add_plugin(routes[5], {
        request_jq_program = ".",
        request_jq_program_options = {
          sort_keys = true,
        }
      })

      -- pretty output
      add_plugin(routes[6], {
        request_jq_program = ".",
        request_jq_program_options = {
          compact_output = false,
        }
      })

      -- custom if_media_type
      add_plugin(routes[7], {
        request_jq_program = ".foo",
        request_if_media_type = {
          "application/json",
          "application/x-json-custom",
        },
      })
    end

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "jq"
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

    it("noop and no error on empty data", function()
      local r = assert(client:send {
        method  = "POST",
        path    = "/request",
        headers = {
          ["Host"] = "test1.example.com",
          ["Content-Type"] = "text/plain",
        },
        body = "",
      })
      local req = assert.request(r)
      assert.same("", req.kong_request.post_data.text)
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

    it("filters with ascii_output", function()
      local r = assert(client:send {
        method  = "POST",
        path    = "/request",
        headers = {
          ["Host"] = "test4.example.com",
          ["Content-Type"] = "application/json",
        },
        body = {
          foo = "baré",
        },
      })
      local json = assert.request(r).has.jsonbody()
      assert.same("\"bar\\u00e9\"\n", json.data)
    end)

    it("filters with sorted keys", function()
      local r = assert(client:send {
        method  = "POST",
        path    = "/request",
        headers = {
          ["Host"] = "test5.example.com",
          ["Content-Type"] = "application/json",
        },
        body = {
          foo = "bar",
          bar = "foo",
        },
      })
      local json = assert.request(r).has.jsonbody()
      assert.same("{\"bar\":\"foo\",\"foo\":\"bar\"}\n", json.data)
    end)

    it("filters with pretty output", function()
      local r = assert(client:send {
        method  = "POST",
        path    = "/request",
        headers = {
          ["Host"] = "test6.example.com",
          ["Content-Type"] = "application/json",
        },
        body = {
          foo = "bar",
        },
      })
      local json = assert.request(r).has.jsonbody()
      assert.same([[{
  "foo": "bar"
}
]], json.data)
    end)

    it("does not filter with different media type", function()
      local r = assert(client:send {
        method  = "POST",
        path    = "/request",
        headers = {
          ["Host"] = "test1.example.com",
          ["Content-Type"] = "text/plain",
        },
        body = [[{"foo":"bar"}]],
      })
      local req = assert.request(r)
      assert.same([[{"foo":"bar"}]], req.kong_request.post_data.text)
    end)

    it("filters with explicit media type", function()
      local r = assert(client:send {
        method  = "POST",
        path    = "/request",
        headers = {
          ["Host"] = "test7.example.com",
          ["Content-Type"] = "application/x-json-custom",
        },
        body = [[{"foo":"bar"}]],
      })
      local req = assert.request(r)
      assert.same("\"bar\"\n", req.kong_request.post_data.text)
    end)
  end)
end)

end
