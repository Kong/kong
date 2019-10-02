local helpers = require "spec.helpers"
local cjson = require "cjson"

local slots_default, slots_max = 10000, 2^16

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_multipart = fn("multipart/form-data")
  local test_json = fn("application/json")

  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
  it(title .. " with application/json", test_json)
end

for _, strategy in helpers.each_strategy() do

describe("Admin API: #" .. strategy, function()
  local client
  local bp
  local db

  lazy_setup(function()

    bp, db = helpers.get_db_utils(strategy, {})

    assert(helpers.start_kong{
      database = strategy
    })
    client = assert(helpers.admin_client())
  end)

  lazy_teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("/upstreams #" .. strategy, function()
    describe("POST", function()
      before_each(function()
        assert(db:truncate("upstreams"))
      end)
      it_content_types("creates an upstream with defaults", function(content_type)
        return function()
          local res = client:post("/upstreams", {
            body = { name = "my.upstream" },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(slots_default, json.slots)
          assert.are.equal("none", json.hash_on)
          assert.are.equal("none", json.hash_fallback)
          assert.equal(ngx.null, json.hash_on_header)
          assert.equal(ngx.null, json.hash_fallback_header)
        end
      end)
      it_content_types("creates an upstream without defaults", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my.upstream",
              slots = 10,
              hash_on = "consumer",
              hash_fallback = "ip",
              hash_on_header = "HeaderName",
              hash_fallback_header = "HeaderFallback",
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(10, json.slots)
          assert.are.equal("consumer", json.hash_on)
          assert.are.equal("ip", json.hash_fallback)
          assert.are.equal("HeaderName", json.hash_on_header)
          assert.are.equal("HeaderFallback", json.hash_fallback_header)
        end
      end)
      it_content_types("creates an upstream with hash_on cookie parameters", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my.upstream",
              hash_on = "cookie",
              hash_on_cookie = "CookieName1",
              hash_on_cookie_path = "/foo",
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal("cookie", json.hash_on)
          assert.are.equal("CookieName1", json.hash_on_cookie)
          assert.are.equal("/foo", json.hash_on_cookie_path)
        end
      end)
      it_content_types("creates an upstream with 2 header hashes", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my.upstream",
              slots = 10,
              hash_on = "header",
              hash_fallback = "header",
              hash_on_header = "HeaderName1",
              hash_fallback_header = "HeaderName2",
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(10, json.slots)
          assert.are.equal("header", json.hash_on)
          assert.are.equal("header", json.hash_fallback)
          assert.are.equal("HeaderName1", json.hash_on_header)
          assert.are.equal("HeaderName2", json.hash_fallback_header)
        end
      end)
      it_content_types("creates an upstream with " .. slots_max .. " slots", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my.upstream",
              slots = slots_max,
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(slots_max, json.slots)
        end
      end)
      it_content_types("creates an upstream with host header", function(content_type)
        return function()
          local res = client:post("/upstreams", {
            body = { name = "my.upstream", host_header = "localhost" },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(slots_default, json.slots)
          assert.are.equal("none", json.hash_on)
          assert.are.equal("none", json.hash_fallback)
          assert.equal(ngx.null, json.hash_on_header)
          assert.equal(ngx.null, json.hash_fallback_header)
          assert.equal("localhost", json.host_header)
        end
      end)
      describe("errors", function()
        it("handles malformed JSON body", function()
          local res = assert(client:request {
            method = "POST",
            path = "/upstreams",
            body = '{"hello": "world"',
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.res_status(400, res)
          assert.equal('{"message":"Cannot parse JSON body"}', body)
        end)
        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing parameter
            local res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                slots = 50,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equals("schema violation", json.name)
            assert.same({ name = "required field missing" }, json.fields)

            -- Invalid name parameter
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "some invalid host name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equals("schema violation", json.name)
            assert.same({ name = "Invalid name; must be a valid hostname" }, json.fields)

            -- Invalid slots parameter
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                slots = 2^16+1
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equals("schema violation", json.name)
            assert.same({ slots = "value should be between 10 and 65536" }, json.fields)

            -- Invalid hash_on entries
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "something that is invalid",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equals("schema violation", json.name)
            assert.same({ hash_on = "expected one of: none, consumer, ip, header, cookie" }, json.fields)

            -- Invalid hash_fallback entries
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "consumer",
                hash_fallback = "something that is invalid",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equals("schema violation", json.name)
            assert.same({
              ["@entity"] = { [[failed conditional validation given value of field 'hash_on']] },
              hash_fallback = "expected one of: none, ip, header, cookie",
            }, json.fields)

            -- same hash entries
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "consumer",
                hash_fallback = "consumer",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              ["@entity"] = { [[failed conditional validation given value of field 'hash_on']] },
              hash_fallback = "expected one of: none, ip, header, cookie",
            }, json.fields)

            -- Invalid header
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "header",
                hash_fallback = "consumer",
                hash_on_header = "not a <> valid <> header name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equals("bad header name 'not a <> valid <> header name', allowed characters are A-Z, a-z, 0-9, '_', and '-'",
                          json.fields.hash_on_header)

            -- Invalid fallback header
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "consumer",
                hash_fallback = "header",
                hash_fallback_header = "not a <> valid <> header name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equals("bad header name 'not a <> valid <> header name', allowed characters are A-Z, a-z, 0-9, '_', and '-'",
                          json.fields.hash_fallback_header)

            -- Same headers
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "header",
                hash_fallback = "header",
                hash_on_header = "headername",
                hash_fallback_header = "headername",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equal("schema violation", json.name)
            assert.same({ ["@entity"] = { "values of these fields must be distinct: 'hash_on_header', 'hash_fallback_header'" }, }, json.fields)

            -- Cookie with hash_fallback
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "cookie",
                hash_on_cookie = "cookiename",
                hash_fallback = "header",
                hash_fallback_header = "Cool-Header",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              ["@entity"] = { [[failed conditional validation given value of field 'hash_on']] },
              hash_fallback = "expected one of: none",
            }, json.fields)

            -- No headername provided
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "header",
                hash_fallback = "header",
                hash_on_header = nil,  -- not given
                hash_fallback_header = "HeaderName",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              ["@entity"] = { [[failed conditional validation given value of field 'hash_on']] },
              hash_on_header = "required field missing",
            }, json.fields)

            -- No fallback headername provided
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "consumer",
                hash_fallback = "header",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              ["@entity"] = { [[failed conditional validation given value of field 'hash_fallback']] },
              hash_fallback_header = "required field missing",
            }, json.fields)

            -- Invalid cookie
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "cookie",
                hash_on_cookie = "not a <> valid <> cookie name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equals("bad cookie name 'not a <> valid <> cookie name', allowed characters are A-Z, a-z, 0-9, '_', and '-'",
                          json.fields.hash_on_cookie)

            -- Invalid cookie path
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "cookie",
                hash_on_cookie = "hashme",
                hash_on_cookie_path = "not a path",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ hash_on_cookie_path = "should start with: /" }, json.fields)

            -- Invalid cookie in hash fallback
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "consumer",
                hash_fallback = "cookie",
                hash_on_cookie = "not a <> valid <> cookie name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equals("bad cookie name 'not a <> valid <> cookie name', allowed characters are A-Z, a-z, 0-9, '_', and '-'",
                          json.fields.hash_on_cookie)

            -- Invalid cookie path in hash fallback
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "consumer",
                hash_fallback = "cookie",
                hash_on_cookie = "my-cookie",
                hash_on_cookie_path = "not a path",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ hash_on_cookie_path = "should start with: /" }, json.fields)

          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.res_status(201, res)

            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.equal("unique constraint violation", json.name)
            assert.same({ name = "my.upstream" }, json.fields)
          end
        end)
      end)
    end)

    describe("PUT", function()
      before_each(function()
        assert(db:truncate("upstreams"))
      end)

      it_content_types("creates if not exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/upstreams/my-upstream",
            body = {
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my-upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.is_number(json.slots)
        end
      end)
      it_content_types("replaces if exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              slots = 100,
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()

          res = assert(client:send {
            method = "PUT",
            path = "/upstreams/" .. json.id,
            body = {
              name = "my-new-upstream",
              slots = 123,
              created_at = json.created_at
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(200)
          local updated_json = assert.response(res).has.jsonbody()
          assert.equal("my-new-upstream", updated_json.name)
          assert.equal(123, updated_json.slots)
          assert.equal(json.id, updated_json.id)
        end
      end)
      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing parameter
            local res = assert(client:send {
              method = "PUT",
              path = "/upstreams/00000000-0000-0000-0000-000000000001",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.response(res).has.status(400)
            local json = cjson.decode(body)
            assert.same("schema violation (name: required field missing)", json.message)

            -- Invalid parameter
            local res = assert(client:send {
              method = "PUT",
              path = "/upstreams/1.2.3.4", -- ip is not allowed
              body = { created_at = 1461276890000 },
              headers = {["Content-Type"] = content_type}
            })

            body = assert.response(res).has.status(400)
            local json = cjson.decode(body)
            assert.same("Invalid name; no ip addresses allowed", json.message)
          end
        end)
      end)
    end)

    describe("GET", function()
      lazy_setup(function()
        assert(db:truncate("upstreams"))
        bp.upstreams:insert_n(10)
      end)
      lazy_teardown(function()
        assert(db:truncate("upstreams"))
      end)

      it("retrieves the first page", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams"
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal(10, #json.data)
      end)
      it("paginates a set", function()
        local pages = {}
        local offset

        for i = 1, 4 do
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams",
            query = {size = 3, offset = offset}
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()

          if i < 4 then
            assert.equal(3, #json.data)
          else
            assert.equal(1, #json.data)
          end

          if i > 1 then
            -- check all pages are different
            assert.not_same(pages[i-1], json)
          end

          offset = json.offset
          pages[i] = json
        end
      end)
      it("ignores filters", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams",
          query = {foo = "bar"}
        })
        assert.res_status(200, res)
      end)
      it("ignores an invalid body", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams",
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)
      end)

      describe("empty results", function()
        lazy_setup(function()
          assert(db:truncate("upstreams"))
        end)

        it("data property is an empty array", function()
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same({ data = {}, next = ngx.null }, json)
        end)
      end)
    end)

    describe("DELETE", function()
      it("by id", function(content_type)
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              slots = 100,
            },
            headers = { ["Content-Type"] = "application/json" }
          })

          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()

          res = assert(client:send {
            method = "DELETE",
            path = "/upstreams/" .. json.id,
          })

          assert.response(res).has.status(204)
      end)

      it("by name", function(content_type)
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              slots = 100,
            },
            headers = { ["Content-Type"] = "application/json" }
          })

          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()

          res = assert(client:send {
            method = "DELETE",
            path = "/upstreams/" .. json.name,
          })

          assert.response(res).has.status(204)
      end)

      it("after deleting its targets (regression test for #4317)", function(content_type)
        assert(db:truncate("upstreams"))
        assert(db:truncate("targets"))

        client = assert(helpers.admin_client())
        -- create the upstream
        local res = assert(client:send {
          method = "POST",
          path = "/upstreams",
          body = {
            name = "my-upstream",
            slots = 100,
          },
          headers = { ["Content-Type"] = "application/json" }
        })

        assert.response(res).has.status(201)

        client:close()
        client = assert(helpers.admin_client())

        -- create the target
        local res = assert(client:send {
          method = "POST",
          path = "/upstreams/my-upstream/targets",
          body = {
            target = "127.0.0.1:8000",
          },
          headers = { ["Content-Type"] = "application/json" }
        })

        assert.response(res).has.status(201)

        client:close()
        client = assert(helpers.admin_client())

        -- delete the target
        local res = assert(client:send {
          method = "DELETE",
          path = "/upstreams/my-upstream/targets/127.0.0.1:8000",
          headers = { ["Content-Type"] = "application/json" }
        })

        assert.response(res).has.status(204)

        client:close()
        client = assert(helpers.admin_client())

        -- deleting the target does not delete the upstream
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams/my-upstream",
          headers = { ["Content-Type"] = "application/json" }
        })

        assert.response(res).has.status(200)

        client:close()
        client = assert(helpers.admin_client())

        -- delete the upstream
        res = assert(client:send {
          method = "DELETE",
          path = "/upstreams/my-upstream",
        })

        assert.response(res).has.status(204)
      end)

      it("can delete an upstream with targets", function(content_type)
        assert(db:truncate("upstreams"))
        assert(db:truncate("targets"))

        -- create the upstream
        local res = assert(client:send {
          method = "POST",
          path = "/upstreams",
          body = {
            name = "my-upstream",
            slots = 100,
          },
          headers = { ["Content-Type"] = "application/json" }
        })

        assert.response(res).has.status(201)

        client:close()
        client = assert(helpers.admin_client())

        -- create the target
        local res = assert(client:send {
          method = "POST",
          path = "/upstreams/my-upstream/targets",
          body = {
            target = "127.0.0.1:8000",
          },
          headers = { ["Content-Type"] = "application/json" }
        })

        assert.response(res).has.status(201)

        client:close()
        client = assert(helpers.admin_client())

        -- delete the upstream
        res = assert(client:send {
          method = "DELETE",
          path = "/upstreams/my-upstream",
        })

        assert.response(res).has.status(204)
      end)
    end)

    it("returns 405 on invalid method", function()
      local res = assert(client:send {
        method = "DELETE",
        path = "/upstreams",
        headers = { ["Content-Type"] = "application/json" }
      })

      local body = assert.response(res).has.status(405)
      local json = cjson.decode(body)
      assert.same({ message = "Method not allowed" }, json)
    end)
  end)
end)

end
