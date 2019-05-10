local helpers = require "spec.helpers"
local cjson   = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: request-transformer (access) [#" .. strategy .. "]", function()
    local proxy_client
    local upstream_host = helpers.mock_upstream_host .. ':' .. helpers.mock_upstream_port

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })

      local route_nph = bp.routes:insert({
        hosts = { "no-preserve-host.test" },
        preserve_host = false,
      })

      local route_ph = bp.routes:insert({
        hosts = { "preserve-host.test" },
        preserve_host = true,
      })

      local route_ph_ah = bp.routes:insert({
        hosts = { "preserve-host-add-host.test" },
        preserve_host = true,
      })

      local route_nph_ah = bp.routes:insert({
        hosts = { "no-preserve-host-add-host.test" },
        preserve_host = false,
      })

      local route_ph_rh = bp.routes:insert({
        hosts = { "preserve-host-replace-host.test" },
        preserve_host = true,
      })

      local route_nph_rh = bp.routes:insert({
        hosts = { "no-preserve-host-replace-host.test" },
        preserve_host = false,
      })

      local route_rename_host = bp.routes:insert({
        hosts = { "rename-host.test" },
        preserve_host = false,
      })

      local route_append_host = bp.routes:insert({
        hosts = { "append-host.test" },
        preserve_host = false,
      })

      local route3 = bp.routes:insert({
        hosts = { "test3.com" },
      })

      local route4 = bp.routes:insert({
        hosts = { "test4.com" },
      })

      local route5 = bp.routes:insert({
        hosts = { "test5.com" },
      })

      local route6 = bp.routes:insert({
        hosts = { "test6.com" },
      })

      local route7 = bp.routes:insert({
        hosts = { "test7.com" },
      })

      local route8 = bp.routes:insert({
        hosts = { "test8.com" },
      })

      local route9 = bp.routes:insert({
        hosts = { "test9.com" },
      })

      bp.plugins:insert {
        route = { id = route1.id },
        name     = "request-transformer",
        config   = {
          add = {
            headers     = {"h1:v1", "h2:value:2"}, -- payload containing a colon
            querystring = {"q1:v1"},
            body        = {"p1:v1"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route_nph.id },
        name     = "request-transformer",
        config   = {
          add = {
            headers = {"x-foo:bar"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route_ph.id },
        name     = "request-transformer",
        config   = {
          add = {
            headers = {"x-foo:bar"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route_nph_ah.id },
        name     = "request-transformer",
        config   = {
          add = {
            headers = {"host:added"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route_ph_ah.id },
        name     = "request-transformer",
        config   = {
          add = {
            headers = {"host:added"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route_nph_rh.id },
        name     = "request-transformer",
        config   = {
          replace = {
            headers = {"host:replaced"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route_ph_rh.id },
        name     = "request-transformer",
        config   = {
          replace = {
            headers = {"host:replaced"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route_rename_host.id },
        name     = "request-transformer",
        config   = {
          rename = {
            headers = {"host:foo"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route_append_host.id },
        name     = "request-transformer",
        config   = {
          append = {
            headers = {"host:appended"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route3.id },
        name     = "request-transformer",
        config   = {
          add = {
            headers     = {"x-added:a1", "x-added2:b1", "x-added3:c2"},
            querystring = {"query-added:newvalue", "p1:anything:1"},   -- payload containing a colon
            body        = {"newformparam:newvalue"}
          },
          remove = {
            headers     = {"x-to-remove"},
            querystring = {"toremovequery"}
          },
          append = {
            headers     = {"x-added:a2", "x-added:a3"},
            querystring = {"p1:a2", "p2:b1"}
          },
          replace = {
            headers     = {"x-to-replace:false"},
            querystring = {"toreplacequery:no"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route4.id },
        name     = "request-transformer",
        config   = {
          remove = {
            headers     = {"x-to-remove"},
            querystring = {"q1"},
            body        = {"toremoveform"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route5.id },
        name     = "request-transformer",
        config   = {
          replace = {
            headers     = {"h1:v1"},
            querystring = {"q1:v1"},
            body        = {"p1:v1"}
          }
        }
      }

      bp.plugins:insert {
        route = { id = route6.id },
        name     = "request-transformer",
        config   = {
          append = {
            headers     = {"h1:v1", "h1:v2", "h2:v1",},
            querystring = {"q1:v1", "q1:v2", "q2:v1"},
            body        = {"p1:v1", "p1:v2", "p2:value:1"} -- payload containing a colon
          }
        }
      }

      bp.plugins:insert {
        route = { id = route7.id },
        name     = "request-transformer",
        config   = {
          http_method = "POST"
        }
      }

      bp.plugins:insert {
        route = { id = route8.id },
        name     = "request-transformer",
        config   = {
          http_method = "GET"
        }
      }

      bp.plugins:insert {
        route = { id = route9.id },
        name     = "request-transformer",
        config   = {
          rename = {
            headers     = {"x-to-rename:x-is-renamed"},
            querystring = {"originalparam:renamedparam"},
            body        = {"originalparam:renamedparam"}
          }
        }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    describe("http method", function()
      it("changes the HTTP method from GET to POST", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?hello=world&name=marco",
          headers = {
            host  = "test7.com"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal("POST", json.vars.request_method)
        assert.equal("world", json.uri_args.hello)
        assert.equal("marco", json.uri_args.name)
      end)
      it("changes the HTTP method from POST to GET", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request?hello=world",
          body    = {
            name  = "marco"
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test8.com"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal("GET", json.vars.request_method)
        assert.equal("world", json.uri_args.hello)
        assert.equal("marco", json.uri_args.name)
      end)
    end)
    describe("remove", function()
      it("specified header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "test4.com",
            ["x-to-remove"]      = "true",
            ["x-another-header"] = "true"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.header("x-to-remove")
        assert.request(res).has.header("x-another-header")
      end)
      it("parameters on url encoded form POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            ["toremoveform"] = "yes",
            ["nottoremove"]  = "yes"
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test4.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.formparam("toremoveform")
        local value = assert.request(res).has.formparam("nottoremove")
        assert.equals("yes", value)
      end)
      it("parameters from JSON body in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            ["toremoveform"] = "yes",
            ["nottoremove"]  = "yes"
          },
          headers = {
            host  = "test4.com",
            ["content-type"] = "application/json"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local json = assert.request(res).has.jsonbody()
        assert.is_nil(json.params["toremoveform"])
        assert.equals("yes", json.params["nottoremove"])
      end)
      it("does not fail if JSON body is malformed in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = "malformed json body",
          headers = {
            host             = "test4.com",
            ["content-type"] = "application/json"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equals("json (error)", json.post_data.kind)
        assert.not_nil(json.post_data.error)
      end)
      it("does not fail if body is empty and content type is application/json in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {},
          headers = {
            host             = "test4.com",
            ["content-type"] = "application/json"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equals('{}', json.post_data.text)
        assert.equals("2", json.headers["content-length"])
      end)
      it("does not fail if body is empty in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = "",
          headers = {
            host  = "test4.com"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.same(cjson.null, json.post_data.params)
        assert.equal('', json.post_data.text)
        local value = assert.request(res).has.header("content-length")
        assert.equal("0", value)
      end)
      it("parameters on multipart POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            ["toremoveform"] = "yes",
            ["nottoremove"]  = "yes"
          },
          headers = {
            ["Content-Type"] = "multipart/form-data",
            host             = "test4.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.formparam("toremoveform")
        local value = assert.request(res).has.formparam("nottoremove")
        assert.equals("yes", value)
      end)
      it("args on GET if it exist", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            q1    = "v1",
            q2    = "v2",
          },
          body    = {
            hello = "world"
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test4.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.queryparam("q1")
        local value = assert.request(res).has.queryparam("q2")
        assert.equals("v2", value)
      end)
    end)

    describe("rename", function()

      describe("Host header", function()
        it("rename is no-op for Host", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Content-Type"] = "application/json",
              host             = "rename-host.test"
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          local value = assert.has.header("host", json)
          assert.equals(upstream_host, value)
        end)
      end)

      it("specified header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host                 = "test9.com",
            ["x-to-rename"]      = "true",
            ["x-another-header"] = "true"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.header("x-to-rename")
        assert.request(res).has.header("x-is-renamed")
        assert.request(res).has.header("x-another-header")
      end)
      it("does not add as new header if header does not exist", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            host           = "test9.com",
            ["x-a-header"] = "true",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.header("renamedparam")
        local h_a_header = assert.request(res).has.header("x-a-header")
        assert.equals("true", h_a_header)
      end)
      it("specified parameters in url encoded body on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            originalparam = "yes",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test9.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.formparam("originalparam")
        local value = assert.request(res).has.formparam("renamedparam")
        assert.equals("yes", value)
      end)
      it("does not add as new parameter in url encoded body if parameter does not exist on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            ["x-a-header"] = "true",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test9.com"
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.formparam("renamedparam")
        local value = assert.request(res).has.formparam("x-a-header")
        assert.equals("true", value)
      end)
      it("parameters from JSON body in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            ["originalparam"] = "yes",
            ["nottorename"]   = "yes"
          },
          headers = {
            host  = "test9.com",
            ["content-type"]  = "application/json"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local json = assert.request(res).has.jsonbody()
        assert.is_nil(json.params["originalparam"])
        assert.is_not_nil(json.params["renamedparam"])
        assert.equals("yes", json.params["renamedparam"])
        assert.equals("yes", json.params["nottorename"])
      end)
      it("does not fail if JSON body is malformed in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = "malformed json body",
          headers = {
            host             = "test9.com",
            ["content-type"] = "application/json"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equals("json (error)", json.post_data.kind)
        assert.is_not_nil(json.post_data.error)
      end)
      it("parameters on multipart POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            ["originalparam"] = "yes",
            ["nottorename"]   = "yes"
          },
          headers = {
            ["Content-Type"] = "multipart/form-data",
            host             = "test9.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.formparam("originalparam")
        local value = assert.request(res).has.formparam("renamedparam")
        assert.equals("yes", value)
        local value2 = assert.request(res).has.formparam("nottorename")
        assert.equals("yes", value2)
      end)
      it("args on GET if it exists", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            originalparam = "true",
            nottorename   = "true",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test9.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.queryparam("originalparam")
        local value1 = assert.request(res).has.queryparam("renamedparam")
        assert.equals("true", value1)
        local value2 = assert.request(res).has.queryparam("nottorename")
        assert.equals("true", value2)
      end)
    end)

    describe("rename", function()
      it("specified header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "test9.com",
            ["x-to-rename"]      = "true",
            ["x-another-header"] = "true"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.header("x-to-rename")
        assert.request(res).has.header("x-is-renamed")
        assert.request(res).has.header("x-another-header")
      end)
      it("does not add as new header if header does not exist", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            host           = "test9.com",
            ["x-a-header"] = "true",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.header("renamedparam")
        local h_a_header = assert.request(res).has.header("x-a-header")
        assert.equals("true", h_a_header)
      end)
      it("specified parameters in url encoded body on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            originalparam = "yes",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test9.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.formparam("originalparam")
        local value = assert.request(res).has.formparam("renamedparam")
        assert.equals("yes", value)
      end)
      it("does not add as new parameter in url encoded body if parameter does not exist on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            ["x-a-header"]   = "true",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test9.com"
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.formparam("renamedparam")
        local value = assert.request(res).has.formparam("x-a-header")
        assert.equals("true", value)
      end)
      it("parameters from JSON body in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            ["originalparam"] = "yes",
            ["nottorename"]   = "yes"
          },
          headers = {
            host  = "test9.com",
            ["content-type"]  = "application/json"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local json = assert.request(res).has.jsonbody()
        assert.is_nil(json.params["originalparam"])
        assert.is_not_nil(json.params["renamedparam"])
        assert.equals("yes", json.params["renamedparam"])
        assert.equals("yes", json.params["nottorename"])
      end)
      it("does not fail if JSON body is malformed in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = "malformed json body",
          headers = {
            host             = "test9.com",
            ["content-type"] = "application/json"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equals("json (error)", json.post_data.kind)
        assert.is_not_nil(json.post_data.error)
      end)
      it("parameters on multipart POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            ["originalparam"] = "yes",
            ["nottorename"]   = "yes"
          },
          headers = {
            ["Content-Type"]  = "multipart/form-data",
            host              = "test9.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.formparam("originalparam")
        local value = assert.request(res).has.formparam("renamedparam")
        assert.equals("yes", value)
        local value2 = assert.request(res).has.formparam("nottorename")
        assert.equals("yes", value2)
      end)
      it("args on GET if it exists", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            originalparam    = "true",
            nottorename      = "true",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test9.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.queryparam("originalparam")
        local value1 = assert.request(res).has.queryparam("renamedparam")
        assert.equals("true", value1)
        local value2 = assert.request(res).has.queryparam("nottorename")
        assert.equals("true", value2)
      end)
    end)

    describe("replace", function()

      describe("Host header", function()
        it("preserve_host = true, host change in plugin: transformed host", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Content-Type"] = "application/json",
              host             = "preserve-host-replace-host.test"
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          local value = assert.has.header("host", json)
          assert.equals("replaced", value)
        end)

        it("preserve_host = false, host change in plugin: transformed host", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Content-Type"] = "application/json",
              host             = "no-preserve-host-replace-host.test"
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          local value = assert.has.header("host", json)
          assert.equals("replaced", value)
        end)
      end)

      it("specified header if it exist", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            host  = "test5.com",
            h1    = "V",
            h2    = "v2",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local h_h1 = assert.request(res).has.header("h1")
        assert.equals("v1", h_h1)
        local h_h2 = assert.request(res).has.header("h2")
        assert.equals("v2", h_h2)
      end)
      it("does not add as new header if header does not exist", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = {},
          headers = {
            host  = "test5.com",
            h2    = "v2",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.header("h1")
        local h_h2 = assert.request(res).has.header("h2")
        assert.equals("v2", h_h2)
      end)
      it("specified parameters in url encoded body on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p1    = "v",
            p2    = "v1",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test5.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.formparam("p1")
        assert.equals("v1", value)
        local value = assert.request(res).has.formparam("p2")
        assert.equals("v1", value)
      end)
      it("does not add as new parameter in url encoded body if parameter does not exist on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p2    = "v1",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test5.com"
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.formparam("p1")
        local value = assert.request(res).has.formparam("p2")
        assert.equals("v1", value)
      end)
      it("specified parameters in json body on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p1    = "v",
            p2    = "v1"
          },
          headers = {
            host             = "test5.com",
            ["content-type"] = "application/json"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.request(res).has.jsonbody()
        assert.equals("v1", json.params.p1)
        assert.equals("v1", json.params.p2)
      end)
      it("does not fail if JSON body is malformed in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = "malformed json body",
          headers = {
            host             = "test5.com",
            ["content-type"] = "application/json"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal("json (error)", json.post_data.kind)
        assert.is_not_nil(json.post_data.error)
      end)
      it("does not add as new parameter in json if parameter does not exist on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p2    = "v1",
          },
          headers = {
            host             = "test5.com",
            ["content-type"] = "application/json"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.request(res).has.jsonbody()
        assert.is_nil(json.params.p1)
        assert.equals("v1", json.params.p2)
      end)
      it("specified parameters on multipart POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p1    = "v",
            p2    = "v1",
          },
          headers = {
            ["Content-Type"] = "multipart/form-data",
            host             = "test5.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local value = assert.request(res).has.formparam("p1")
        assert.equals("v1", value)
        local value2 = assert.request(res).has.formparam("p2")
        assert.equals("v1", value2)
      end)
      it("does not add as new parameter if parameter does not exist on multipart POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p2    = "v1",
          },
          headers = {
            ["Content-Type"] = "multipart/form-data",
            host             = "test5.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()

        assert.request(res).has.no.formparam("p1")

        local value = assert.request(res).has.formparam("p2")
        assert.equals("v1", value)
      end)
      it("args on POST if it exist", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          query   = {
            q1    = "v",
            q2    = "v2",
          },
          body    = {
            hello = "world"
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test5.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.queryparam("q1")
        assert.equals("v1", value)
        local value = assert.request(res).has.queryparam("q2")
        assert.equals("v2", value)
      end)
      it("does not add new args on POST if it does not exist", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          query   = {
            q2    = "v2",
          },
          body    = {
            hello = "world"
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test5.com"
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.queryparam("q1")
        local value = assert.request(res).has.queryparam("q2")
        assert.equals("v2", value)
      end)
    end)

    describe("add", function()

      describe("Host header", function()
        it("preserve_host = true, no host change in plugin: preserved host", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Content-Type"] = "application/json",
              host             = "preserve-host.test"
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          local value = assert.has.header("host", json)
          assert.equals("preserve-host.test", value)
        end)

        it("preserve_host = false, no host change in plugin: upstream host", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Content-Type"] = "application/json",
              host             = "no-preserve-host.test"
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          local value = assert.has.header("host", json)
          assert.equals(upstream_host, value)
        end)

        it("preserve_host = true, is no-op for Host: preserved host", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Content-Type"] = "application/json",
              host             = "preserve-host-add-host.test"
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          local value = assert.has.header("host", json)
          assert.equals("preserve-host-add-host.test", value)
        end)

        it("preserve_host = false, is no-op for Host: upstream host", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Content-Type"] = "application/json",
              host             = "no-preserve-host-add-host.test"
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          local value = assert.has.header("host", json)
          assert.equals(upstream_host, value)
        end)
      end)

      it("new headers", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local h_h1 = assert.request(res).has.header("h1")
        assert.equals("v1", h_h1)
        local h_h2 = assert.request(res).has.header("h2")
        assert.equals("value:2", h_h2)
      end)
      it("does not change or append value if header already exists", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            h1    = "v3",
            host  = "test1.com",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local h_h1 = assert.request(res).has.header("h1")
        assert.equals("v3", h_h1)
        local h_h2 = assert.request(res).has.header("h2")
        assert.equals("value:2", h_h2)
      end)
      it("new parameter in url encoded body on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.formparam("hello")
        assert.equals("world", value)
        local value = assert.request(res).has.formparam("p1")
        assert.equals("v1", value)
      end)
      it("does not change or append value to parameter in url encoded body on POST when parameter exists", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p1    = "should not change",
            hello = "world",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.formparam("p1")
        assert.equals("should not change", value)
        local value = assert.request(res).has.formparam("hello")
        assert.equals("world", value)
      end)
      it("new parameter in JSON body on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            ["Content-Type"] = "application/json",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        local params = assert.request(res).has.jsonbody().params
        assert.equals("world", params.hello)
        assert.equals("v1", params.p1)
      end)
      it("does not change or append value to parameter in JSON on POST when parameter exists", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p1    = "this should not change",
            hello = "world",
          },
          headers = {
            ["Content-Type"] = "application/json",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        local params = assert.request(res).has.jsonbody().params
        assert.equals("world", params.hello)
        assert.equals("this should not change", params.p1)
      end)
      it("does not fail if JSON body is malformed in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = "malformed json body",
          headers = {
            host             = "test1.com",
            ["content-type"] = "application/json"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal("json (error)", json.post_data.kind)
        assert.is_not_nil(json.post_data.error)
      end)
      it("new parameter on multipart POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {},
          headers = {
            ["Content-Type"] = "multipart/form-data",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local value = assert.request(res).has.formparam("p1")
        assert.equals("v1", value)
      end)
      it("does not change or append value to parameter on multipart POST when parameter exists", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p1    = "this should not change",
            hello = "world",
          },
          headers = {
            ["Content-Type"] = "multipart/form-data",
            host             = "test1.com"
          },
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local value = assert.request(res).has.formparam("p1")
        assert.equals("this should not change", value)

        local value2 = assert.request(res).has.formparam("hello")
        assert.equals("world", value2)
      end)
      it("new querystring on GET", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            q2    = "v2",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.queryparam("q2")
        assert.equals("v2", value)
        local value = assert.request(res).has.queryparam("q1")
        assert.equals("v1", value)
      end)

      it("does not change or append value to querystring on GET if querystring exists", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            q1    = "v2",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.queryparam("q1")
        assert.equals("v2", value)
      end)
    end)

    describe("append", function()

      describe("Host header", function()
        it("append is no-op for Host", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Content-Type"] = "application/json",
              host             = "append-host.test"
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          local value = assert.has.header("host", json)
          assert.equals(upstream_host, value)
        end)
      end)

      it("new header if header does not exists", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "test6.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local h_h2 = assert.request(res).has.header("h2")
        assert.equals("v1", h_h2)
      end)
      it("values to existing headers", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "test6.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local h_h1 = assert.request(res).has.header("h1")
        assert.same({"v1", "v2"}, h_h1)
      end)
      it("new querystring if querystring does not exists", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test6.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.queryparam("q2")
        assert.equals("v1", value)
      end)
      it("values to existing querystring", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test6.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.queryparam("q1")
        assert.are.same({"v1", "v2"}, value)
      end)
      it("new parameter in url encoded body on POST if it does not exist", function()
        local res = assert( proxy_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test6.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local value = assert.request(res).has.formparam("p1")
        assert.same({"v1", "v2"}, value)

        local value2 = assert.request(res).has.formparam("p2")
        assert.same("value:1", value2)
      end)
      it("values to existing parameter in url encoded body if parameter already exist on POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p1    = "v0",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test6.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local value = assert.request(res).has.formparam("p1")
        assert.same({"v0", "v1", "v2"}, value)

        local value2 = assert.request(res).has.formparam("p2")
        assert.are.same("value:1", value2)
      end)
      it("does not fail if JSON body is malformed in POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = "malformed json body",
          headers = {
            host             = "test6.com",
            ["content-type"] = "application/json"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal("json (error)", json.post_data.kind)
        assert.is_not_nil(json.post_data.error)
      end)
      it("does not change or append value to parameter on multipart POST", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            p1    = "This should not change",
          },
          headers = {
            ["Content-Type"] = "multipart/form-data",
            host             = "test6.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local value = assert.request(res).has.formparam("p1")
        assert.equals("This should not change", value)
      end)
    end)

    describe("remove, replace, add and append ", function()
      it("removes a header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host            = "test3.com",
            ["x-to-remove"] = "true",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.header("x-to-remove")
      end)
      it("replaces value of header, if header exist", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host             = "test3.com",
            ["x-to-replace"] = "true",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local hval = assert.request(res).has.header("x-to-replace")
        assert.equals("false", hval)
      end)
      it("does not add new header if to be replaced header does not exist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "test3.com",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.header("x-to-replace")
      end)
      it("add new header if missing", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "test3.com",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local hval = assert.request(res).has.header("x-added2")
        assert.equals("b1", hval)
      end)
      it("does not add new header if it already exist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host         = "test3.com",
            ["x-added3"] = "c1",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local hval = assert.request(res).has.header("x-added3")
        assert.equals("c1", hval)
      end)
      it("appends values to existing headers", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "test3.com",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        local hval = assert.request(res).has.header("x-added")
        assert.same({"a1", "a2", "a3"}, hval)
      end)
      it("adds new parameters on POST when query string key missing", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            host             = "test3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.queryparam("p2")
        assert.equals("b1", value)
      end)
      it("removes parameters on GET", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            toremovequery = "yes",
            nottoremove   = "yes",
          },
          body    = {
            hello = "world",
          },
          headers = {
            host             = "test3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.request(res).has.no.queryparam("toremovequery")
        local value = assert.request(res).has.queryparam("nottoremove")
        assert.equals("yes", value)
      end)
      it("replaces parameters on GET", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            toreplacequery = "yes",
          },
          body    = {
            hello = "world",
          },
          headers = {
            host             = "test3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.queryparam("toreplacequery")
        assert.equals("no", value)
      end)
      it("does not add new parameter if to be replaced parameters does not exist on GET", function()
        local res = assert( proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host             = "test3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.formparam("toreplacequery")
      end)
      it("adds parameters on GET if it does not exist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host             = "test3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.queryparam("query-added")
        assert.equals("newvalue", value)
      end)
      it("does not add new parameter if to be added parameters already exist on GET", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            ["query-added"] = "oldvalue",
          },
          headers = {
            host             = "test3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.queryparam("query-added")
        assert.equals("oldvalue", value)
      end)
      it("appends parameters on GET", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            q1    = "20",
          },
          body    = {
            hello = "world",
          },
          headers = {
            host             = "test3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.queryparam("p1")
        assert.equals("anything:1", value[1])
        assert.equals("a2", value[2])
        local value = assert.request(res).has.queryparam("q1")
        assert.equals("20", value)
      end)
    end)
  end)
end
