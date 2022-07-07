local admin_api = require "spec.fixtures.admin_api"
local helpers = require "spec.helpers"
local cjson   = require "cjson"
local pl_file = require "pl.file"


local function count_log_lines(pattern)
  local cfg = helpers.test_conf
  local logs = pl_file.read(cfg.prefix .. "/" .. cfg.proxy_error_log)
  local _, count = logs:gsub(pattern, "")
  return count
end


for _, strategy in helpers.each_strategy() do
describe("Plugin: request-transformer(access) [#" .. strategy .. "]", function()
  local client

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "plugins",
    })

    local route1 = bp.routes:insert({
      hosts = { "test1.test" }
    })
    local route2 = bp.routes:insert({
      hosts = { "test2.test" },
      preserve_host = true,
    })
    local route3 = bp.routes:insert({
      hosts = { "test3.test" }
    })
    local route4 = bp.routes:insert({
      hosts = { "test4.test" }
    })
    local route5 = bp.routes:insert({
      hosts = { "test5.test" }
    })
    local route6 = bp.routes:insert({
      hosts = { "test6.test" }
    })
    local route7 = bp.routes:insert({
      hosts = { "test7.test" }
    })
    local route8 = bp.routes:insert({
      hosts = { "test8.test" }
    })
    local route9 = bp.routes:insert({
      hosts = { "test9.test" }
    })
    local route10 = bp.routes:insert({
      hosts = { "test10.test" },
      paths = { "~/requests/user1/(?P<user1>\\w+)/user2/(?P<user2>\\S+)" },
      strip_path = false
    })
    local route11 = bp.routes:insert({
      hosts = { "test11.test" },
      paths = { "~/requests/user1/(?P<user1>\\w+)/user2/(?P<user2>\\S+)" }
    })
    local route12 = bp.routes:insert({
      hosts = { "test12.test" },
      paths = { "/requests/" },
      strip_path = false
    })
    local route13 = bp.routes:insert({
      hosts = { "test13.test" },
      paths = { "~/requests/user1/(?P<user1>\\w+)/user2/(?P<user2>\\S+)" }
    })
    local route14 = bp.routes:insert({
      hosts = { "test14.test" },
      paths = { "~/user1/(?P<user1>\\w+)/user2/(?P<user2>\\S+)" }
    })
    local route15 = bp.routes:insert({
      hosts = { "test15.test" },
      paths = { "~/requests/user1/(?<user1>\\w+)/user2/(?<user2>\\S+)" },
      strip_path = false
    })
    local route16 = bp.routes:insert({
      hosts = { "test16.test" },
      paths = { "~/requests/user1/(?<user1>\\w+)/user2/(?<user2>\\S+)" },
      strip_path = false
    })
    local route17 = bp.routes:insert({
      hosts = { "test17.test" },
      paths = { "~/requests/user1/(?<user1>\\w+)/user2/(?<user2>\\S+)" },
      strip_path = false
    })
    local route18 = bp.routes:insert({
      hosts = { "test18.test" },
      paths = { "~/requests/user1/(?<user1>\\w+)/user2/(?<user2>\\S+)" },
      strip_path = false
    })
    local route19 = bp.routes:insert({
      hosts = { "test19.test" },
      paths = { "~/requests/user1/(?<user1>\\w+)/user2/(?<user2>\\S+)" },
      strip_path = false
    })
    local route20 = bp.routes:insert({
      hosts = { "test20.test" }
    })
    local route21 = bp.routes:insert({
      hosts = { "test21.test" }
    })
    local route22 = bp.routes:insert({
      hosts = { "test22.test" }
    })
    local route23 = bp.routes:insert({
      hosts = { "test23.test" },
      paths = { "/request" }
    })
    local route24 = bp.routes:insert({
      hosts = { "test24.test" }
    })
    local route25 = bp.routes:insert({
      hosts = { "test25.test" }
    })
    local route26 = bp.routes:insert({
      hosts = { "test26.test" }
    })

    local route27 = bp.routes:insert({
      hosts = { "test27.test" }
    })

    local route28 = bp.routes:insert({
      hosts = { "test28.test" }
    })

    bp.plugins:insert {
      route = { id = route1.id },
      name = "request-transformer",
      config = {
        add = {
          headers = {"h1:v1", "h2:value:2"}, -- payload containing a colon
          querystring = {"q1:v1"},
          body = {"p1:v1"}
        }
      }
    }
    bp.plugins:insert {
      route = { id = route2.id },
      name = "request-transformer",
      config = {
        add = {
          headers = {"host:mark"}
        }
      }
    }
    bp.plugins:insert {
      route = { id = route3.id },
      name = "request-transformer",
      config = {
        add = {
          headers = {"x-added:a1", "x-added2:b1", "x-added3:c2"},
          querystring = {"query-added:newvalue", "p1:anything:1"},   -- payload containing a colon
          body = {"newformparam:newvalue"}
        },
        remove = {
          headers = {"x-to-remove"},
          querystring = {"toremovequery"}
        },
        append = {
          headers = {"x-added:a2", "x-added:a3"},
          querystring = {"p1:a2", "p2:b1"}
        },
        replace = {
          headers = {"x-to-replace:false"},
          querystring = {"toreplacequery:no"}
        }
      }
    }
    bp.plugins:insert {
      route = { id = route4.id },
      name = "request-transformer",
      config = {
        remove = {
          headers = {"x-to-remove"},
          querystring = {"q1"},
          body = {"toremoveform"}
        }
      }
    }
    bp.plugins:insert {
      route = { id = route5.id },
      name = "request-transformer",
      config = {
        replace = {
          headers = {"h1:v1"},
          querystring = {"q1:v1"},
          body = {"p1:v1"}
        }
      }
    }
    bp.plugins:insert {
      route = { id = route6.id },
      name = "request-transformer",
      config = {
        append = {
          headers = {"h1:v1", "h1:v2", "h2:v1",},
          querystring = {"q1:v1", "q1:v2", "q2:v1"},
          body = {"p1:v1", "p1:v2", "p2:value:1"}     -- payload containing a colon
        }
      }
    }
    bp.plugins:insert {
      route = { id = route7.id },
      name = "request-transformer",
      config = {
        http_method = "POST"
      }
    }
    bp.plugins:insert {
      route = { id = route8.id },
      name = "request-transformer",
      config = {
        http_method = "GET"
      }
    }

    bp.plugins:insert {
      route = { id = route9.id },
      name = "request-transformer",
      config = {
        rename = {
          headers = {"x-to-rename:x-is-renamed"},
          querystring = {"originalparam:renamedparam"},
          body = {"originalparam:renamedparam"}
        }
      }
    }

    bp.plugins:insert {
      route = { id = route10.id },
      name = "request-transformer",
      config = {
        add = {
          querystring = {"uri_param1:$(uri_captures.user1)", "uri_param2[some_index][1]:$(uri_captures.user2)"},
        }
      }
    }

    bp.plugins:insert {
      route = { id = route11.id },
      name = "request-transformer",
      config = {
        replace = {
          uri = "/requests/user2/$(uri_captures.user2)/user1/$(uri_captures.user1)",
        }
      }
    }

    bp.plugins:insert {
      route = { id = route12.id },
      name = "request-transformer",
      config = {
        add = {
          querystring = {"uri_param1:$(uri_captures.user1 or 'default1')", "uri_param2:$(uri_captures.user2 or 'default2')"},
        }
      }
    }

    bp.plugins:insert {
      route = { id = route13.id },
      name = "request-transformer",
      config = {
        replace = {
          uri = "/requests/user2/$(10 * uri_captures.user1)",
        }
      }
    }

    bp.plugins:insert {
      route = { id = route14.id },
      name = "request-transformer",
      config = {
        replace = {
          uri = "/requests$(uri_captures[0])",
        }
      }
    }

    bp.plugins:insert {
      route = { id = route15.id },
      name = "request-transformer",
      config = {
        add = {
          querystring = {"uri_param1:$(uri_captures.user1)", "uri_param2:$(headers.host)"},
          headers = {"x-test-header:$(query_params.q1)"}
        },
        remove = {
          querystring = {"q1"},
        }
      }
    }

    bp.plugins:insert {
      route = { id = route16.id },
      name = "request-transformer",
      config = {
        replace = {
          querystring = {"q2:$(headers['x-remove-header'])"},
        },
        add = {
          querystring = {"q1:$(uri_captures.user1)"},
          headers = {"x-test-header:$(headers['x-remove-header'])"}
        },
        remove = {
          headers = {"x-remove-header"}
        },
      }
    }

    bp.plugins:insert {
      route = { id = route17.id },
      name = "request-transformer",
      config = {
        replace = {
          querystring = {"q2:$(headers['x-replace-header'])"},
          headers = {"x-replace-header:the new value"}
        },
        add = {
          querystring = {"q1:$(uri_captures.user1)"},
          headers = {"x-test-header:$(headers['x-replace-header'])"}
        }
      }
    }

    bp.plugins:insert {
      route = { id = route18.id },
      name = "request-transformer",
      config = {
        add = {
          querystring = {[[q1:$('$(uri_captures.user1)')]]},
        }
      }
    }

    bp.plugins:insert {
      route = { id = route19.id },
      name = "request-transformer",
      config = {
        add = {
          -- will trigger a runtime error
          querystring = {[[q1:$(ERROR())]]},
        }
      }
    }

    bp.plugins:insert {
      route = { id = route20.id },
      name = "request-transformer",
      config = {
        http_method = "POST",
        add = {
          headers = {
            "Content-Type:application/json"
          },
          body = { "body:somecontent" }
        },
      }
    }

    do
      -- 2 plugins:
      -- pre-function: plugin to inject a shared value in the kong.ctx.shared table
      -- transformer: pick up the injected value and add to the query string
      bp.plugins:insert {
        route = { id = route21.id },
        name = "pre-function",
        config = {
          access = {
            [[
              kong.ctx.shared.my_version = "1.2.3"
            ]]
          },
        }
      }
      bp.plugins:insert {
        route = { id = route21.id },
        name = "request-transformer",
        config = {
          add = {
            querystring = {"shared_param1:$(shared.my_version)"},
          }
        }
      }
    end
    bp.plugins:insert {
      route = { id = route22.id },
      name = "request-transformer",
      config = {
        http_method = "POST",
        remove = {
          headers = { "Authorization" },
        },
        add = {
          headers = { "Authorization:Basic test" },
        },
      },
    }

    bp.plugins:insert {
      route = { id = route23.id },
      name = "request-transformer",
      config = {}
    }

    bp.plugins:insert {
      route = { id = route24.id },
      name = "request-transformer",
      config = {
        add = {
          headers = { "x-user-agent:$(foo(headers[\"User-Agent\"]) == \"table\" and headers[\"User-Agent\"][1] or headers[\"User-Agent\"])", },
        },
      }
    }

    bp.plugins:insert {
      route = { id = route25.id },
      name = "request-transformer",
      config = {
        add = {
          headers = { "X-Foo-Transformed:$(type(headers[\"X-Foo\"]) == \"table\" and headers[\"X-Foo\"][1] .. \"-first\" or headers[\"X-Foo\"])", },
        },
      }
    }

    bp.plugins:insert {
      route = { id = route26.id },
      name = "request-transformer",
      config = {
        add = {
          headers = {"X-aDDed:a1", "x-aDDed2:b1", "x-Added3:c2"},
        },
        remove = {
          headers = {"X-To-Remove"},
        },
        append = {
          headers = {"X-aDDed:a2", "X-aDDed:a3"},
        },
        replace = {
          headers = {"x-to-Replace:false"},
        }
      }
    }

    bp.plugins:insert {
      route = { id = route27.id },
      name = "request-transformer",
      config = {
        replace = {
          uri = "/requests/tést",
        }
      }
    }

    -- transformer attempts to inject a value in ngx.ctx.shared, but that will result in an invalid template
    -- which provokes a failure
    bp.plugins:insert {
      route = { id = route28.id },
      name = "request-transformer",
      config = {
        add = {
          headers = { "X-Write-Attempt:$(shared.written = true)" },
        }
      }
    }

    assert(helpers.start_kong({
      database = strategy,
      plugins = "bundled, request-transformer",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then client:close() end
  end)

  describe("http method", function()
    it("changes the HTTP method from GET to POST", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request?hello=world&name=marco",
        headers = {
          host = "test7.test"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("POST", json.vars.request_method)
      assert.equal("world", json.uri_args.hello)
      assert.equal("marco", json.uri_args.name)
    end)
    it("changes the HTTP method from POST to GET", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request?hello=world",
        body = {
          name = "marco"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test8.test"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("GET", json.vars.request_method)
      assert.equal("world", json.uri_args.hello)
      assert.equal("marco", json.uri_args.name)
    end)
    it("changes the HTTP method from GET to POST and adds JSON body", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test20.test",
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.request(r).has.jsonbody()
      assert.equal("POST", json.vars.request_method)
      assert.is_nil(json.post_data.error)
      local header_content_type = assert.request(r).has.header("Content-Type")
      assert.equals("application/json", header_content_type)
    end)
  end)
  describe("remove", function()
    it("specified header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test4.test",
          ["x-to-remove"] = "true",
          ["x-another-header"] = "true"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("x-to-remove")
      assert.request(r).has.header("x-another-header")
    end)
    it("parameters on url encoded form POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["toremoveform"] = "yes",
          ["nottoremove"] = "yes"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test4.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.formparam("toremoveform")
      local value = assert.request(r).has.formparam("nottoremove")
      assert.equals("yes", value)
    end)
    it("parameters from JSON body in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["toremoveform"] = "yes",
          ["nottoremove"] = "yes"
        },
        headers = {
          host = "test4.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local json = assert.request(r).has.jsonbody()
      assert.is_nil(json.params["toremoveform"])
      assert.equals("yes", json.params["nottoremove"])
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test4.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals("json (error)", json.post_data.kind)
      assert.not_nil(json.post_data.error)
    end)
    it("does not fail if body is empty and content type is application/json in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {},
        headers = {
          host = "test4.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals('{}', json.post_data.text)
      assert.equals("2", json.headers["content-length"])
    end)
    it("does not fail if body is empty in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "",
        headers = {
          host = "test4.test"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.same(cjson.null, json.post_data.params)
      assert.equal('', json.post_data.text)
      local value = assert.request(r).has.header("content-length")
      assert.equal("0", value)
    end)
    it("parameters on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["toremoveform"] = "yes",
          ["nottoremove"] = "yes"
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test4.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.formparam("toremoveform")
      local value = assert.request(r).has.formparam("nottoremove")
      assert.equals("yes", value)
    end)
    it("args on GET if it exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          q1 = "v1",
          q2 = "v2",
        },
        body = {
          hello = "world"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test4.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.queryparam("q1")
      local value = assert.request(r).has.queryparam("q2")
      assert.equals("v2", value)
    end)
  end)

  describe("rename", function()
    it("specified header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test9.test",
          ["x-to-rename"] = "true",
          ["x-another-header"] = "true"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("x-to-rename")
      assert.request(r).has.header("x-is-renamed")
      assert.request(r).has.header("x-another-header")
    end)
    it("does not add as new header if header does not exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        body = {},
        headers = {
          host = "test9.test",
          ["x-a-header"] = "true",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("renamedparam")
      local h_a_header = assert.request(r).has.header("x-a-header")
      assert.equals("true", h_a_header)
    end)
    it("specified parameters in url encoded body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          originalparam = "yes",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.formparam("originalparam")
      local value = assert.request(r).has.formparam("renamedparam")
      assert.equals("yes", value)
    end)
    it("does not add as new parameter in url encoded body if parameter does not exist on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["x-a-header"] = "true",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.test"
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.formparam("renamedparam")
      local value = assert.request(r).has.formparam("x-a-header")
      assert.equals("true", value)
    end)
    it("parameters from JSON body in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["originalparam"] = "yes",
          ["nottorename"] = "yes"
        },
        headers = {
          host = "test9.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local json = assert.request(r).has.jsonbody()
      assert.is_nil(json.params["originalparam"])
      assert.is_not_nil(json.params["renamedparam"])
      assert.equals("yes", json.params["renamedparam"])
      assert.equals("yes", json.params["nottorename"])
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test9.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals("json (error)", json.post_data.kind)
      assert.is_not_nil(json.post_data.error)
    end)
    it("parameters on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["originalparam"] = "yes",
          ["nottorename"] = "yes"
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test9.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.formparam("originalparam")
      local value = assert.request(r).has.formparam("renamedparam")
      assert.equals("yes", value)
      local value2 = assert.request(r).has.formparam("nottorename")
      assert.equals("yes", value2)
    end)
    it("args on GET if it exists", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          originalparam = "true",
          nottorename = "true",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.queryparam("originalparam")
      local value1 = assert.request(r).has.queryparam("renamedparam")
      assert.equals("true", value1)
      local value2 = assert.request(r).has.queryparam("nottorename")
      assert.equals("true", value2)
    end)
  end)

  describe("rename", function()
    it("specified header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test9.test",
          ["x-to-rename"] = "true",
          ["x-another-header"] = "true"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("x-to-rename")
      assert.request(r).has.header("x-is-renamed")
      assert.request(r).has.header("x-another-header")
    end)
    it("does not add as new header if header does not exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        body = {},
        headers = {
          host = "test9.test",
          ["x-a-header"] = "true",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("renamedparam")
      local h_a_header = assert.request(r).has.header("x-a-header")
      assert.equals("true", h_a_header)
    end)
    it("specified parameters in url encoded body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          originalparam = "yes",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.formparam("originalparam")
      local value = assert.request(r).has.formparam("renamedparam")
      assert.equals("yes", value)
    end)
    it("does not add as new parameter in url encoded body if parameter does not exist on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["x-a-header"] = "true",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.test"
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.formparam("renamedparam")
      local value = assert.request(r).has.formparam("x-a-header")
      assert.equals("true", value)
    end)
    it("parameters from JSON body in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["originalparam"] = "yes",
          ["nottorename"] = "yes"
        },
        headers = {
          host = "test9.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local json = assert.request(r).has.jsonbody()
      assert.is_nil(json.params["originalparam"])
      assert.is_not_nil(json.params["renamedparam"])
      assert.equals("yes", json.params["renamedparam"])
      assert.equals("yes", json.params["nottorename"])
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test9.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals("json (error)", json.post_data.kind)
      assert.is_not_nil(json.post_data.error)
    end)
    it("parameters on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["originalparam"] = "yes",
          ["nottorename"] = "yes"
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test9.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.formparam("originalparam")
      local value = assert.request(r).has.formparam("renamedparam")
      assert.equals("yes", value)
      local value2 = assert.request(r).has.formparam("nottorename")
      assert.equals("yes", value2)
    end)
    it("args on GET if it exists", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          originalparam = "true",
          nottorename = "true",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.queryparam("originalparam")
      local value1 = assert.request(r).has.queryparam("renamedparam")
      assert.equals("true", value1)
      local value2 = assert.request(r).has.queryparam("nottorename")
      assert.equals("true", value2)
    end)
  end)

  describe("replace", function()
    it("specified header if it exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        body = {},
        headers = {
          host = "test5.test",
          h1 = "V",
          h2 = "v2",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h1 = assert.request(r).has.header("h1")
      assert.equals("v1", h_h1)
      local h_h2 = assert.request(r).has.header("h2")
      assert.equals("v2", h_h2)
    end)
    it("does not add as new header if header does not exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        body = {},
        headers = {
          host = "test5.test",
          h2 = "v2",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("h1")
      local h_h2 = assert.request(r).has.header("h2")
      assert.equals("v2", h_h2)
    end)
    it("specified parameters in url encoded body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "v",
          p2 = "v1",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test5.test"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.formparam("p1")
      assert.equals("v1", value)
      local value = assert.request(r).has.formparam("p2")
      assert.equals("v1", value)
    end)
    it("does not add as new parameter in url encoded body if parameter does not exist on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p2 = "v1",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test5.test"
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.formparam("p1")
      local value = assert.request(r).has.formparam("p2")
      assert.equals("v1", value)
    end)
    it("specified parameters in json body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "v",
          p2 = "v1"
        },
        headers = {
          host = "test5.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.request(r).has.jsonbody()
      assert.equals("v1", json.params.p1)
      assert.equals("v1", json.params.p2)
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test5.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("json (error)", json.post_data.kind)
      assert.is_not_nil(json.post_data.error)
    end)
    it("does not add as new parameter in json if parameter does not exist on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p2 = "v1",
        },
        headers = {
          host = "test5.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.request(r).has.jsonbody()
      assert.is_nil(json.params.p1)
      assert.equals("v1", json.params.p2)
    end)
    it("specified parameters on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "v",
          p2 = "v1",
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test5.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local value = assert.request(r).has.formparam("p1")
      assert.equals("v1", value)
      local value2 = assert.request(r).has.formparam("p2")
      assert.equals("v1", value2)
    end)
    it("does not add as new parameter if parameter does not exist on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p2 = "v1",
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test5.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()

      assert.request(r).has.no.formparam("p1")

      local value = assert.request(r).has.formparam("p2")
      assert.equals("v1", value)
    end)
    it("args on POST if it exist", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        query = {
          q1 = "v",
          q2 = "v2",
        },
        body = {
          hello = "world"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test5.test"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("v1", value)
      local value = assert.request(r).has.queryparam("q2")
      assert.equals("v2", value)
    end)
    it("does not add new args on POST if it does not exist", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        query = {
          q2 = "v2",
        },
        body = {
          hello = "world"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test5.test"
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.queryparam("q1")
      local value = assert.request(r).has.queryparam("q2")
      assert.equals("v2", value)
    end)

    pending("escape UTF-8 characters when replacing upstream path - enable after Kong 2.4", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/wrong_path",
        headers = {
          host = "test27.test"
        }
      })
      assert.response(r).has.status(200)
      local body = assert(assert.response(r).has.jsonbody())
      assert.equals(helpers.mock_upstream_url ..
                    "/requests/t%C3%A9st", body.url)
    end)
  end)

  describe("add", function()
    it("new headers", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test1.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h1 = assert.request(r).has.header("h1")
      assert.equals("v1", h_h1)
      local h_h2 = assert.request(r).has.header("h2")
      assert.equals("value:2", h_h2)
    end)
    it("does not change or append value if header already exists", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          h1 = "v3",
          host = "test1.test",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h1 = assert.request(r).has.header("h1")
      assert.equals("v3", h_h1)
      local h_h2 = assert.request(r).has.header("h2")
      assert.equals("value:2", h_h2)
    end)
    it("new parameter in url encoded body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test1.test"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.formparam("hello")
      assert.equals("world", value)
      local value = assert.request(r).has.formparam("p1")
      assert.equals("v1", value)
    end)
    it("does not change or append value to parameter in url encoded body on POST when parameter exists", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "should not change",
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test1.test"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.formparam("p1")
      assert.equals("should not change", value)
      local value = assert.request(r).has.formparam("hello")
      assert.equals("world", value)
    end)
    it("new parameter in JSON body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "application/json",
          host = "test1.test"
        }
      })
      assert.response(r).has.status(200)
      local params = assert.request(r).has.jsonbody().params
      assert.equals("world", params.hello)
      assert.equals("v1", params.p1)
    end)
    it("does not change or append value to parameter in JSON on POST when parameter exists", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "this should not change",
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "application/json",
          host = "test1.test"
        }
      })
      assert.response(r).has.status(200)
      local params = assert.request(r).has.jsonbody().params
      assert.equals("world", params.hello)
      assert.equals("this should not change", params.p1)
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test1.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("json (error)", json.post_data.kind)
      assert.is_not_nil(json.post_data.error)
    end)
    it("new parameter on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {},
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test1.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local value = assert.request(r).has.formparam("p1")
      assert.equals("v1", value)
    end)
    it("does not change or append value to parameter on multipart POST when parameter exists", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "this should not change",
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test1.test"
        },
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local value = assert.request(r).has.formparam("p1")
      assert.equals("this should not change", value)

      local value2 = assert.request(r).has.formparam("hello")
      assert.equals("world", value2)
    end)
    it("new querystring on GET", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          q2 = "v2",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test1.test"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("q2")
      assert.equals("v2", value)
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("v1", value)
    end)
    it("does not change or append value to querystring on GET if querystring exists", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          q1 = "v2",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test1.test"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("v2", value)
    end)
    it("should not change the host header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          ["Content-Type"] = "application/json",
          host = "test2.test"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      local value = assert.has.header("host", json)
      assert.equals("test2.test", value)
    end)
  end)

  describe("append ", function()
    it("new header if header does not exists", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test6.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h2 = assert.request(r).has.header("h2")
      assert.equals("v1", h_h2)
    end)
    it("values to existing headers", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test6.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h1 = assert.request(r).has.header("h1")
      assert.same({"v1", "v2"}, h_h1)
    end)

    it("can append a value with '#' (regression test for #29)", function()
      local route = admin_api.routes:insert({
        hosts = { "test_append_hash.test" }
      })
      admin_api.plugins:insert {
        route = { id = route.id },
        name = "request-transformer",
        config = {
          append = {
            headers = {"h1:v1", "h1:v2", "h1:#value_with_hash", "h2:v1",},
            querystring = {"q1:v1", "q1:v2", "q2:v1"},
            body = {"p1:v1", "p1:v2", "p2:value:1"}     -- payload containing a colon
          }
        }
      }
      local r
      helpers.wait_until(function()
        r = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test_append_hash.test"
          }
        })
        local body = r:read_body()
        return string.find(body, "h1", 1, true)
      end, 10)
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h1 = assert.request(r).has.header("h1")
      assert.same({"v1", "v2", "#value_with_hash"}, h_h1)
    end)

    it("new querystring if querystring does not exists", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test6.test"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("q2")
      assert.equals("v1", value)
    end)
    it("values to existing querystring", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test6.test"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("q1")
      assert.are.same({"v1", "v2"}, value)
    end)
    it("new parameter in url encoded body on POST if it does not exist", function()
      local r = assert( client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test6.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local value = assert.request(r).has.formparam("p1")
      assert.same({"v1", "v2"}, value)

      local value2 = assert.request(r).has.formparam("p2")
      assert.same("value:1", value2)
    end)
    it("values to existing parameter in url encoded body if parameter already exist on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "v0",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test6.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local value = assert.request(r).has.formparam("p1")
      assert.same({"v0", "v1", "v2"}, value)

      local value2 = assert.request(r).has.formparam("p2")
      assert.are.same("value:1", value2)
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test6.test",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("json (error)", json.post_data.kind)
      assert.is_not_nil(json.post_data.error)
    end)
    it("does not change or append value to parameter on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "This should not change",
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test6.test"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local value = assert.request(r).has.formparam("p1")
      assert.equals("This should not change", value)
    end)
  end)

  describe("remove, replace, add and append ", function()
    it("removes a header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.test",
          ["x-to-remove"] = "true",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("x-to-remove")
    end)
    it("replaces value of header, if header exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.test",
          ["x-to-replace"] = "true",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-to-replace")
      assert.equals("false", hval)
    end)
    it("does not add new header if to be replaced header does not exist", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.test",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("x-to-replace")
    end)
    it("add new header if missing", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.test",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-added2")
      assert.equals("b1", hval)
    end)
    it("does not add new header if it already exist", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.test",
          ["x-added3"] = "c1",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-added3")
      assert.equals("c1", hval)
    end)
    it("appends values to existing headers", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.test",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-added")
      assert.same({"a1", "a2", "a3"}, hval)
    end)
    it("adds new parameters on POST when query string key missing", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("p2")
      assert.equals("b1", value)
    end)
    it("removes parameters on GET", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          toremovequery = "yes",
          nottoremove = "yes",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.queryparam("toremovequery")
      local value = assert.request(r).has.queryparam("nottoremove")
      assert.equals("yes", value)
    end)
    it("replaces parameters on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          toreplacequery = "yes",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("toreplacequery")
      assert.equals("no", value)
    end)
    it("does not add new parameter if to be replaced parameters does not exist on GET", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.formparam("toreplacequery")
    end)
    it("adds parameters on GET if it does not exist", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("query-added")
      assert.equals("newvalue", value)
    end)
    it("does not add new parameter if to be added parameters already exist on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          ["query-added"] = "oldvalue",
        },
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("query-added")
      assert.equals("oldvalue", value)
    end)
    it("appends parameters on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          q1 = "20",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("p1")
      assert.equals("anything:1", value[1])
      assert.equals("a2", value[2])
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("20", value)
    end)

    it("removes a header -- ignore case", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test26.test",
          ["x-to-remove"] = "true",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("X-To-Remove")
    end)
    it("replaces value of header, if header exist -- don't change header case", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test26.test",
          ["x-to-replace"] = "true",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-to-Replace")
      assert.equals("false", hval)
    end)
    it("add new header if missing -- keep configured case", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test26.test",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-aDDed2")
      assert.equals("b1", hval)
    end)
    it("does not add new header if it already exist -- keep request case", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test26.test",
          ["x-added3"] = "c1",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-added3")
      assert.equals("c1", hval)
    end)
    it("appends values to existing headers -- keep config case", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test26.test",
          ["X-addeD"] = "a0",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("X-aDDed")
      assert.same({"a0", "a2", "a3"}, hval)
    end)
    it("appends values to added headers -- keep 'add' config case", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test26.test",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("X-Added")
      assert.same({"a1", "a2", "a3"}, hval)
    end)
    it("adds new parameters on POST when query string key missing", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("p2")
      assert.equals("b1", value)
    end)
    it("removes parameters on GET", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          toremovequery = "yes",
          nottoremove = "yes",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.queryparam("toremovequery")
      local value = assert.request(r).has.queryparam("nottoremove")
      assert.equals("yes", value)
    end)
    it("replaces parameters on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          toreplacequery = "yes",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("toreplacequery")
      assert.equals("no", value)
    end)
    it("does not add new parameter if to be replaced parameters does not exist on GET", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.formparam("toreplacequery")
    end)
    it("adds parameters on GET if it does not exist", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("query-added")
      assert.equals("newvalue", value)
    end)
    it("does not add new parameter if to be added parameters already exist on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          ["query-added"] = "oldvalue",
        },
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("query-added")
      assert.equals("oldvalue", value)
    end)
    it("appends parameters on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          q1 = "20",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("p1")
      assert.equals("anything:1", value[1])
      assert.equals("a2", value[2])
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("20", value)
    end)
  end)



  describe("request rewrite using template", function()
    it("template as querystring parameters on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/user1/foo/user2/bar",
        query = {
          q1 = "20",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test10.test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      local body = assert.response(r).has.status(200)
      local json_body = cjson.decode(body)
      local value = assert.request(r).has.queryparam("uri_param1")
      assert.equals("foo", value)
      assert.equals("/requests/user1/foo/user2/bar?q1=20&uri_param1=foo&uri_param2%5Bsome_index%5D%5B1%5D=bar",
                    json_body.vars.request_uri)
    end)
    it("should update request path using hash", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/user1/foo/user2/bar",
        headers = {
          host = "test11.test",
        }
      })
      assert.response(r).has.status(200)
      local body = assert(assert.response(r).has.jsonbody())
      assert.equals(helpers.mock_upstream_url ..
                    "/requests/user2/bar/user1/foo", body.url)
    end)
    it("should not add querystring if hash missing", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/",
        query = {
          q1 = "20",
        },
        headers = {
          host = "test12.test",
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.queryparam("q1")
      local value = assert.request(r).has.queryparam("uri_param1")
      assert.equals("default1", value)
      value = assert.request(r).has.queryparam("uri_param2")
      assert.equals("default2", value)
    end)
    it("should fail when uri template is not a proper expression", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/user1/foo/user2/bar",
        headers = {
          host = "test13.test",
        }
      })
      assert.response(r).has.status(500)
    end)
    it("should not fail when uri template rendered using index", function()
      local r = assert(client:send {
        method = "GET",
        path = "/user1/foo/user2/bar",
        headers = {
          host = "test14.test",
        }
      })
      assert.response(r).has.status(200)
      local body = assert(assert.response(r).has.jsonbody())
      assert.equals(helpers.mock_upstream_url ..
                    "/requests/user1/foo/user2/bar", body.url)
    end)
    it("validate using headers/req_querystring for rendering templates",
      function()
        local r = assert(client:send {
          method = "GET",
          path = "/requests/user1/foo/user2/bar",
          query = {
            q1 = "20",
          },
          headers = {
            host = "test15.test",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(r).has.status(200)
        assert.request(r).has.no.queryparam("q1")
        local value = assert.request(r).has.queryparam("uri_param1")
        assert.equals("foo", value)
        value = assert.request(r).has.queryparam("uri_param2")
        assert.equals("test15.test", value)
        value = assert.request(r).has.header("x-test-header")
        assert.equals("20", value)
      end)
    it("validate that removed header can be used as template", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/user1/foo/user2/bar",
        query = {
          q2 = "20",
        },
        headers = {
          host = "test16.test",
          ["x-remove-header"] = "its a test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.header("x-remove-header")
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("foo", value)
      value = assert.request(r).has.queryparam("q2")
      assert.equals("its a test", value)
      value = assert.request(r).has.header("x-test-header")
      assert.equals("its a test", value)
    end)
    it("validate template will be rendered with old value of replaced header",
      function()
        local r = assert(client:send {
          method = "GET",
          path = "/requests/user1/foo/user2/bar",
          query = {
            q2 = "20",
          },
          headers = {
            host = "test17.test",
            ["x-replace-header"] = "the old value",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(r).has.status(200)
        local value = assert.request(r).has.queryparam("q1")
        assert.equals("foo", value)
        value = assert.request(r).has.queryparam("q2")
        assert.equals("the old value", value)
        value = assert.request(r).has.header("x-test-header")
        assert.equals("the old value", value)
        value = assert.request(r).has.header("x-replace-header")
        assert.equals("the new value", value)
      end)
    it("validate template can be escaped",
      function()
        local r = assert(client:send {
          method = "GET",
          path = "/requests/user1/foo/user2/bar",
          query = {
            q2 = "20",
          },
          headers = {
            host = "test18.test",
            ["x-replace-header"] = "the old value",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(r).has.status(200)
        local value = assert.request(r).has.queryparam("q1")
        assert.equals([[$(uri_captures.user1)]], value)
        value = assert.request(r).has.queryparam("q2")
        assert.equals("20", value)
      end)
    it("rendering error (query) should fail when rendering errors out", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/user1/foo/user2/bar",
        query = {
          q2 = "20",
        },
        headers = {
          host = "test19.test",
          ["x-replace-header"] = "the old value",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(500)
    end)
    it("rendering error (header) is correctly propagated in error.log, issue #25", function()
      local pattern = [[error:%[string "TMP"%]:4: attempt to call global 'foo' %(a nil value%)]]
      local start_count = count_log_lines(pattern)

      local r = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "test24.test",
        }
      })
      assert.response(r).has.status(500)

      helpers.wait_until(function()
        local count = count_log_lines(pattern)
        return count - start_count >= 1 -- Kong 2.2+ == 1, Pre 2.2 == 2
      end, 5)
    end)
    it("type function is available in template environment", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test25.test",
          ["X-Foo"] = { "1", "2", },
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h1 = assert.request(r).has.header("X-Foo-Transformed")
      assert.equals("1-first", h_h1)
    end)
    it("can inject a value from 'kong.ctx.shared'", function()
      local r = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "test21.test",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("shared_param1")
      assert.equals("1.2.3", value)
    end)
    it("cannot write a value in `kong.ctx.shared`", function()
      local r = client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "test28.test",
        }
      }
      assert.response(r).has.status(500)
    end)
  end)
  describe("remove then add header (regression test)", function()
    it("header already exists in request", function()
      local r = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "test22.test",
          ["Authorization"] = "Basic dGVzdDp0ZXN0",
          ["Content-Type"] = "application/json",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.header("authorization")
      assert.equals("Basic test", value)
    end)
    it("header does not exist in request", function()
      local r = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "test22.test",
          ["Content-Type"] = "application/json",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.header("authorization")
      assert.equals("Basic test", value)
    end)
  end)
  describe("query parameters are not #urlencoded to upstream URL", function()
    local expected = "$&+,/:;?@"
    it("when plugin is not configured", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request?expected=" .. expected, -- Use inline to keep from getting URL encoded
        headers = {
          host = "test23.test"
        }
      })
      local res = assert.response(r).has.status(200)
      local body = cjson.decode(res)
      local expected_url = helpers.mock_upstream_url .. "/?expected=" .. expected
      assert.equals(expected_url, body.url)
    end)
  end)
end)
end
