local helpers = require "spec.helpers"
local cjson = require "cjson"
local escape = require("socket.url").escape
local Errors  = require "kong.db.errors"
local utils   = require "kong.tools.utils"


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_multipart = fn("multipart/form-data")
  local test_json = fn("application/json")

  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
  it(title .. " with application/json", test_json)
end


local gensym
do
  local i = 0
  gensym = function()
    i = i + 1
    return "abc def " .. i  -- containing space for urlencoded test
  end
end

for _, strategy in helpers.each_strategy() do

describe("Admin API (#" .. strategy .. "): ", function()
  local bp
  local db
  local client

  lazy_setup(function()
    bp, db = helpers.get_db_utils(strategy, {
      "kongsumers",
      "plugins",
    }, {
      "rewriter",
    })
    assert(helpers.start_kong({
      database = strategy,
      plugins = "bundled,rewriter",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
  end)

  before_each(function()
    client = helpers.admin_client()
  end)

  after_each(function()
    if client then client:close() end
  end)

  describe("/kongsumers", function()
    describe("POST", function()
      it_content_types("creates a kongsumer", function(content_type)
        return function()
          local username = gensym()
          local res = assert(client:send {
            method = "POST",
            path = "/kongsumers",
            body = {
              username = username,
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal(username, json.username)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
        end
      end)
      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/kongsumers",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.equal("schema violation", json.name)
            assert.same(
              { "at least one of these fields must be non-empty: 'custom_id', 'username'" },
              json.fields["@entity"]
            )
          end
        end)
        it_content_types("returns 409 on conflicting username", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()
            local res = assert(client:send {
              method = "POST",
              path = "/kongsumers",
              body = {
                username = kongsumer.username,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.equal("unique constraint violation", json.name)
            assert.equal("UNIQUE violation detected on '{username=\"" ..
                         kongsumer.username .. "\"}'", json.message)
          end
        end)
        it_content_types("returns 400 on conflicting custom_id", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()
            local res = assert(client:send {
              method = "POST",
              path = "/kongsumers",
              body = {
                username = "tom",
                custom_id = kongsumer.custom_id,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.equal("unique constraint violation", json.name)
            assert.equal("UNIQUE violation detected on '{custom_id=\"" ..
                         kongsumer.custom_id .. "\"}'", json.message)
          end
        end)
        it("returns 415 on invalid content-type", function()
          local res = assert(client:request {
            method = "POST",
            path = "/kongsumers",
            body = '{"hello": "world"}',
            headers = {["Content-Type"] = "invalid"}
          })
          assert.res_status(415, res)
        end)
        it("returns 415 on missing content-type with body ", function()
          local res = assert(client:request {
            method = "POST",
            path = "/kongsumers",
            body = "invalid"
          })
          assert.res_status(415, res)
        end)
        it("returns 400 on missing body with application/json", function()
          local res = assert(client:request {
            method = "POST",
            path = "/kongsumers",
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ message = "Cannot parse JSON body" }, json)
        end)
        it("returns 400 on missing body with multipart/form-data", function()
          local res = assert(client:request {
            method = "POST",
            path = "/kongsumers",
            headers = {["Content-Type"] = "multipart/form-data"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equals("schema violation", json.name)
          assert.same(
            { "at least one of these fields must be non-empty: 'custom_id', 'username'" },
            json.fields["@entity"])
        end)
        it("returns 400 on missing body with multipart/x-www-form-urlencoded", function()
          local res = assert(client:request {
            method = "POST",
            path = "/kongsumers",
            headers = {["Content-Type"] = "application/x-www-form-urlencoded"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equals("schema violation", json.name)
          assert.same(
            { "at least one of these fields must be non-empty: 'custom_id', 'username'" },
            json.fields["@entity"])
        end)
        it("returns 400 on missing body with no content-type header", function()
          local res = assert(client:request {
            method = "POST",
            path = "/kongsumers",
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equals("schema violation", json.name)
          assert.same(
            { "at least one of these fields must be non-empty: 'custom_id', 'username'" },
            json.fields["@entity"])
        end)
      end)
    end)

    describe("GET", function()
      before_each(function()
        assert(db:truncate("kongsumers"))
        bp.kongsumers:insert_n(10)
      end)
      lazy_teardown(function()
        assert(db:truncate("kongsumers"))
        db:truncate("plugins")
      end)

      it("retrieves the first page", function()
        local res = assert(client:send {
          method = "GET",
          path = "/kongsumers"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(10, #json.data)
      end)
      it("paginates a set", function()
        local pages = {}
        local offset

        for i = 1, 4 do
          local res = assert(client:send {
            method = "GET",
            path = "/kongsumers",
            query = {size = 3, offset = offset}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

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
      it("allows filtering by custom_id", function()
        local custom_id = gensym()
        local c = bp.kongsumers:insert({ custom_id = custom_id })

        local res = client:get("/kongsumers?custom_id=" .. custom_id)
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(1, #json.data)
        assert.same(c, json.data[1])
      end)
    end)
    it("returns 405 on invalid method", function()
      local methods = {"DELETE", "PATCH"}
      for i = 1, #methods do
        local res = assert(client:send {
          method = methods[i],
          path = "/kongsumers",
          body = {}, -- tmp: body to allow POST/PUT to work
          headers = {["Content-Type"] = "application/json"}
        })
        local body = assert.response(res).has.status(405)
        local json = cjson.decode(body)
        assert.same({ message = "Method not allowed" }, json)
      end
    end)

    describe("/kongsumers/{kongsumer}", function()
      describe("GET", function()
        it("retrieves by id", function()
          local kongsumer = bp.kongsumers:insert()
          local res = assert(client:send {
            method = "GET",
            path = "/kongsumers/" .. kongsumer.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(kongsumer, json)
        end)
        it("retrieves by username", function()
          local kongsumer = bp.kongsumers:insert()
          local res = assert(client:send {
            method = "GET",
            path = "/kongsumers/" .. kongsumer.username
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(kongsumer, json)
        end)
        it("retrieves by urlencoded username", function()
          local kongsumer = bp.kongsumers:insert()
          local res = assert(client:send {
            method = "GET",
            path = "/kongsumers/" .. escape(kongsumer.username)
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(kongsumer, json)
        end)
        it("returns 404 if not found", function()
          local res = assert(client:send {
            method = "GET",
            path = "/kongsumers/_inexistent_"
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        it_content_types("updates by id", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()
            local new_username = gensym()
            local res = assert(client:send {
              method = "PATCH",
              path = "/kongsumers/" .. kongsumer.id,
              body = {
                username = new_username,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(new_username, json.username)
            assert.equal(kongsumer.id, json.id)

            local in_db = assert(db.kongsumers:select {id = kongsumer.id})
            assert.same(json, in_db)
          end
        end)
        it_content_types("updates by username", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()
            local new_username = gensym()
            local res = assert(client:send {
              method = "PATCH",
              path = "/kongsumers/" .. kongsumer.username,
              body = {
                username = new_username,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(new_username, json.username)
            assert.equal(kongsumer.id, json.id)

            local in_db = assert(db.kongsumers:select {id = kongsumer.id})
            assert.same(json, in_db)
          end
        end)
        it_content_types("updates by username and custom_id with previous values", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()
            local res = assert(client:send {
              method = "PATCH",
              path = "/kongsumers/" .. kongsumer.username,
              body = {
                username = kongsumer.username,
                custom_id = kongsumer.custom_id,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(kongsumer.username, json.username)
            assert.equal(kongsumer.custom_id, json.custom_id)
            assert.equal(kongsumer.id, json.id)

            local in_db = assert(db.kongsumers:select {id = kongsumer.id})
            assert.same(json, in_db)
          end
        end)

        describe("errors", function()
          it_content_types("returns 404 if not found", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/kongsumers/_inexistent_",
                body = {
                 username = gensym(),
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.res_status(404, res)
            end
          end)
          it("returns 415 on invalid content-type", function()
            local kongsumer = bp.kongsumers:insert()
            local res = assert(client:request {
              method = "PATCH",
              path = "/kongsumers/" .. kongsumer.id,
              body = '{"hello": "world"}',
              headers = {["Content-Type"] = "invalid"}
            })
            assert.res_status(415, res)
          end)
          it("returns 415 on missing content-type with body ", function()
            local kongsumer = bp.kongsumers:insert()
            local res = assert(client:request {
              method = "PATCH",
              path = "/kongsumers/" .. kongsumer.id,
              body = "invalid"
            })
            assert.res_status(415, res)
          end)
          it("returns 400 on missing body with application/json", function()
            local kongsumer = bp.kongsumers:insert()
            local res = assert(client:request {
              method = "PATCH",
              path = "/kongsumers/" .. kongsumer.id,
              headers = {["Content-Type"] = "application/json"}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Cannot parse JSON body" }, json)
          end)
        end)
      end)

      describe("PUT", function()
        it_content_types("creates if not exists", function(content_type)
          return function()
            local custom_id = gensym()
            local id = utils.uuid()
            local res = client:put("/kongsumers/" .. id, {
              body    = { custom_id = custom_id },
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(custom_id, json.custom_id)
            assert.same(id, json.id)
          end
        end)

        it_content_types("creates if not exists by username", function(content_type)
          return function()
            local name = gensym()
            local res = client:put("/kongsumers/" .. name, {
              body    = {},
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(name, json.username)
            assert.equal(cjson.null, json.custom_id)
          end
        end)

        it_content_types("replaces if found", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()
            local new_username = gensym()
            local res = client:put("/kongsumers/" .. kongsumer.id, {
              body    = { username = new_username },
              headers = { ["Content-Type"] = content_type }
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(new_username, json.username)

            local in_db = assert(db.kongsumers:select({ id = kongsumer.id }, { nulls = true }))
            assert.same(json, in_db)
          end
        end)

        it_content_types("replaces if found by username", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()
            local new_custom_id = gensym()
            local res = client:put("/kongsumers/" .. kongsumer.username, {
              body    = { custom_id = new_custom_id },
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(kongsumer.username, json.username)
            assert.equal(new_custom_id, json.custom_id)

            local id = json.id
            res = client:put("/kongsumers/" .. kongsumer.username, {
              body    = {},
              headers = { ["Content-Type"] = content_type }
            })
            body = assert.res_status(200, res)
            json = cjson.decode(body)
            assert.equal(id, json.id)
            assert.equal(kongsumer.username, json.username)
            assert.equal(cjson.null, json.custom_id)
          end
        end)

        describe("errors", function()
          it("handles malformed JSON body", function()
            local kongsumer = bp.kongsumers:insert()
            local res = client:put("/kongsumers/" .. kongsumer.id, {
              body    = '{"hello": "world"',
              headers = { ["Content-Type"] = "application/json" }
            })
            local body = assert.res_status(400, res)
            assert.equal('{"message":"Cannot parse JSON body"}', body)
          end)

          it_content_types("handles invalid input", function(content_type)
            return function()
              -- Missing params
              local res = client:put("/kongsumers/" .. utils.uuid(), {
                body = {},
                headers = { ["Content-Type"] = content_type }
              })
              local body = assert.res_status(400, res)
              assert.same({
                code     = Errors.codes.SCHEMA_VIOLATION,
                name     = "schema violation",
                fields   = {
                  ["@entity"] = {
                    "at least one of these fields must be non-empty: 'custom_id', 'username'"
                  }
                },
                message = "schema violation (at least one of these fields must be non-empty: 'custom_id', 'username')"
              }, cjson.decode(body))
            end
          end)
        end)
      end)

      describe("DELETE", function()
        it("deletes by id", function()
          local kongsumer = bp.kongsumers:insert()
          local res = assert(client:send {
            method = "DELETE",
            path = "/kongsumers/" .. kongsumer.id
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)
        end)
        it("deletes by username", function()
          local kongsumer = bp.kongsumers:insert()
          local res = assert(client:send {
            method = "DELETE",
            path = "/kongsumers/" .. kongsumer.username
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)
        end)
      end)
    end)
  end)

  describe("/kongsumers/{username_or_id}/plugins", function()
    before_each(function()
      db.plugins:truncate()
    end)
    describe("POST", function()
      local inputs = {
        ["application/x-www-form-urlencoded"] = {
          name = "rewriter",
          ["config.value"] = "potato",
        },
        ["application/json"] = {
          name = "rewriter",
          config = {
            value = "potato",
          }
        }
      }

      for content_type, input in pairs(inputs) do
        it("creates a plugin config using a kongsumer id with " .. content_type, function()
          local kongsumer = bp.kongsumers:insert()
          local res = assert(client:send {
            method = "POST",
            path = "/kongsumers/" .. kongsumer.id .. "/plugins",
            body = input,
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("rewriter", json.name)
          assert.same("potato", json.config.value)
        end)
        it("creates a plugin config using a kongsumer username with " .. content_type, function()
          local kongsumer = bp.kongsumers:insert()
          local res = assert(client:send {
            method = "POST",
            path = "/kongsumers/" .. kongsumer.username .. "/plugins",
            body = input,
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("rewriter", json.name)
          assert.same("potato", json.config.value)
        end)
      end

      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()
            local res = assert(client:send {
              method = "POST",
              path = "/kongsumers/" .. kongsumer.id .. "/plugins",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              code = Errors.codes.SCHEMA_VIOLATION,
              name = "schema violation",
              fields = {
                name = "required field missing"
              },
              message = "schema violation (name: required field missing)",
            }, json)
          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()
            -- insert initial plugin
            local res = assert(client:send {
              method = "POST",
              path = "/kongsumers/" .. kongsumer.id .. "/plugins",
              body = {
                name = "rewriter",
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.response(res).has.status(201)
            assert.response(res).has.jsonbody()

            -- do it again, to provoke the error
            res = assert(client:send {
              method = "POST",
              path = "/kongsumers/" .. kongsumer.id .. "/plugins",
              body = {
                name = "rewriter",
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.response(res).has.status(409)
            local json = assert.response(res).has.jsonbody()
            assert.same({
              code = Errors.codes.UNIQUE_VIOLATION,
              name = "unique constraint violation",
              message = [[UNIQUE violation detected on '{service=null,]] ..
                        [[name="rewriter",route=null,kongsumer={id="]] ..
                        kongsumer.id .. [["}}']],
              fields = {
                name = "rewriter",
                kongsumer = {
                  id = kongsumer.id,
                },
                route = ngx.null,
                service = ngx.null,
              },
            }, json)
          end
        end)
      end)
    end)

    describe("GET", function()
      it("retrieves the first page", function()
        local kongsumer = bp.kongsumers:insert()
        bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }})

        local res = assert(client:send {
          method = "GET",
          path = "/kongsumers/" .. kongsumer.id .. "/plugins"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
      end)
      it("ignores an invalid body", function()
        local kongsumer = bp.kongsumers:insert()
        local res = assert(client:send {
          method = "GET",
          path = "/kongsumers/" .. kongsumer.id .. "/plugins",
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)
      end)
    end)

  end)


  describe("/kongsumers/{username_or_id}/plugins/{plugin}", function()

    describe("GET", function()

      it("retrieves by id", function()
        local kongsumer = bp.kongsumers:insert()
        local plugin = bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }}, { nulls = true })

        local res = assert(client:send {
          method = "GET",
          path = "/kongsumers/" .. kongsumer.id .. "/plugins/" .. plugin.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(plugin, json)
      end)
      it("retrieves by kongsumer id when it has spaces", function()
        local kongsumer = bp.kongsumers:insert()
        local plugin = bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }}, { nulls = true })

        local res = assert(client:send {
          method = "GET",
          path = "/kongsumers/" .. kongsumer.id .. "/plugins/" .. plugin.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(plugin, json)
      end)
      it("only retrieves if associated to the correct kongsumer", function()
        local kongsumer = bp.kongsumers:insert()
        local plugin = bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }})

        -- Create an kongsumer and try to query our plugin through it
        local w_kongsumer = bp.kongsumers:insert {
          custom_id = "wc",
          username = "wrong-kongsumer"
        }

        -- Try to request the plugin through it (belongs to the fixture kongsumer instead)
        local res = assert(client:send {
          method = "GET",
          path = "/kongsumers/" .. w_kongsumer.id .. "/plugins/" .. plugin.id
        })
        assert.res_status(404, res)
      end)
      it("ignores an invalid body", function()
        local kongsumer = bp.kongsumers:insert()
        local plugin = bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }})

        local res = assert(client:send {
          method = "GET",
          path = "/kongsumers/" .. kongsumer.id .. "/plugins/" .. plugin.id,
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)
      end)
    end)

    describe("PATCH", function()

      local inputs = {
        ["application/x-www-form-urlencoded"] = {
          ["config.value"] = "updated",
        },
        ["application/json"] = {
          config = {
            value = "updated",
          }
        }
      }

      for content_type, input in pairs(inputs) do

        it("updates if found with " .. content_type, function()
          local kongsumer = bp.kongsumers:insert()
          local plugin = bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }})

          local res = assert(client:send {
            method = "PATCH",
            path = "/kongsumers/" .. kongsumer.id .. "/plugins/" .. plugin.id,
            body = input,
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("updated", json.config.value)
          assert.equal(plugin.id, json.id)

          local in_db = assert(db.plugins:select({ id = plugin.id }, { nulls = true }))
          assert.same(json, in_db)
        end)

        it("doesn't override a plugin config if partial with " .. content_type, function()
        -- This is delicate since a plugin config is a text field in a DB like Cassandra
          local kongsumer = bp.kongsumers:insert()
          local plugin = bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }})

          local err
          plugin, err = db.plugins:update(
            { id = plugin.id },
            {
              name = "rewriter",
              route = plugin.route,
              service = plugin.service,
              kongsumer = plugin.kongsumer,
              config = {
                value = "potato",
                extra = "extra1",
              }
            }
          )
          assert.is_nil(err)
          assert.equal("potato", plugin.config.value)
          assert.equal("extra1", plugin.config.extra )

          local res = assert(client:send {
            method = "PATCH",
            path = "/kongsumers/" .. kongsumer.id .. "/plugins/" .. plugin.id,
            body = input,
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("updated", json.config.value)
          assert.equal("extra1", json.config.extra)

          plugin = assert(db.plugins:select { id = plugin.id })
          assert.equal("updated", plugin.config.value)
          assert.equal("extra1", plugin.config.extra)
        end)
      end

      it_content_types("updates the enabled property", function(content_type)
        return function()
          local kongsumer = bp.kongsumers:insert()
          local plugin = bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }})

          local res = assert(client:send {
            method = "PATCH",
            path = "/kongsumers/" .. kongsumer.id .. "/plugins/" .. plugin.id,
            body = {
              name = "rewriter",
              enabled = false
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.False(json.enabled)

          plugin = assert(db.plugins:select{ id = plugin.id })
          assert.False(plugin.enabled)
        end
      end)
      describe("errors", function()
        it_content_types("returns 404 if not found", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()

            local res = assert(client:send {
              method = "PATCH",
              path = "/kongsumers/" .. kongsumer.id .. "/plugins/b6cca0aa-4537-11e5-af97-23a06d98af51",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            assert.res_status(404, res)
          end
        end)
        it_content_types("handles invalid input", function(content_type)
          return function()
            local kongsumer = bp.kongsumers:insert()
            local plugin = bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }})

            local res = assert(client:send {

              method = "PATCH",
              path = "/kongsumers/" .. kongsumer.id .. "/plugins/" .. plugin.id,
              body = {
                name = "foo"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)

            assert.equals("schema violation", json.name)
            assert.equals("plugin 'foo' not enabled; add it to the 'plugins' configuration property", json.fields.name)
          end
        end)
      end)
    end)

    describe("PUT", function()
      local inputs = {
        ["application/x-www-form-urlencoded"] = {
          name = "rewriter",
          ["config.value"] = "updated",
        },
        ["application/json"] = {
          name = "rewriter",
          config = {
            value = "updated",
          }
        }
      }

      for content_type, input in pairs(inputs) do
        it("creates if not found with " .. content_type, function()
          local kongsumer = bp.kongsumers:insert()
          local plugin_id = utils.uuid()

          local res = assert(client:send {
            method = "PUT",
            path = "/kongsumers/" .. kongsumer.id .. "/plugins/" .. plugin_id,
            body = input,
            headers = { ["Content-Type"] = content_type },
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("updated", json.config.value)
          assert.equal(plugin_id, json.id)

          local in_db = assert(db.plugins:select({
            id = plugin_id,
          }, { nulls = true }))
          assert.same(json, in_db)
        end)

        it("updates if found with " .. content_type, function()
          local kongsumer = bp.kongsumers:insert()
          local plugin = bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }})

          local res = assert(client:send {
            method = "PUT",
            path = "/kongsumers/" .. kongsumer.id .. "/plugins/" .. plugin.id,
            body = input,
            headers = { ["Content-Type"] = content_type },
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("updated", json.config.value)
          assert.equal(plugin.id, json.id)

          local in_db = assert(db.plugins:select({
            id = plugin.id,
          }, { nulls = true }))
          assert.same(json, in_db)
        end)
      end
    end)

    describe("DELETE", function()
      it("deletes a plugin configuration", function()
        local kongsumer = bp.kongsumers:insert()
        local plugin = bp.rewriter_plugins:insert({ kongsumer = { id = kongsumer.id }})

        local res = assert(client:send {
          method = "DELETE",
          path = "/kongsumers/" .. kongsumer.id .. "/plugins/" .. plugin.id
        })
        assert.res_status(204, res)
      end)
      describe("errors", function()
        it("returns 404 if not found", function()
          local kongsumer = bp.kongsumers:insert()

          local res = assert(client:send {
            method = "DELETE",
            path = "/kongsumers/" .. kongsumer.id .. "/plugins/fafafafa-1234-baba-5678-cececececece"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end)

end
