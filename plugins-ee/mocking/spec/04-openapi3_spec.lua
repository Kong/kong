-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_path = require "pl.path"

local PLUGIN_NAME = "mocking"

local function structure_like(source, target)
  for k, v in pairs(source) do
    local source_type = type(v)
    local target_value = target[k]
    if source_type ~= type(target_value) then
      return false, string.format("%s(%s) and %s(%s) are not the same type", v, source_type, target_value, type(target_value))
    end
    if source_type == "table" then
      local ok, err = structure_like(v, target_value)
      if not ok then
        return false, err
      end
    end
  end
  return true, nil
end

local fixture_path
do
  -- this code will get debug info and from that determine the file
  -- location, so fixtures can be found based of this path
  local info = debug.getinfo(function()
  end)
  fixture_path = info.source
  if fixture_path:sub(1, 1) == "@" then
    fixture_path = fixture_path:sub(2, -1)
  end
  fixture_path = pl_path.splitpath(fixture_path) .. "/fixtures/"
end

local function read_fixture(filename)
  local content = assert(helpers.utils.readfile(fixture_path .. filename))
  return content
end

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local spec_contents = {
      yaml = read_fixture("openapi_3.yaml"),
      json = read_fixture("openapi_3.json"),
    }

    for type, spec_content in pairs(spec_contents) do
      describe("[#" .. type .. "]", function()
        local client
        local db_strategy = strategy ~= "off" and strategy or nil

        lazy_setup(function()
          local bp, db = helpers.get_db_utils(db_strategy, {
            "routes",
            "services",
            "plugins"
          }, { PLUGIN_NAME })

          local service = bp.services:insert {
            protocol = "http",
            port = 80,
            host = "mocking.com",
          }

          local route1 = db.routes:insert({
            hosts = { "mocking.com" },
            service = service,
          })
          db.plugins:insert {
            name = PLUGIN_NAME,
            route = { id = route1.id },
            config = {
              api_specification = spec_content
            },
          }

          local route2 = db.routes:insert({
            hosts = { "mocking-codes.com" },
            service = service,
          })
          db.plugins:insert {
            name = PLUGIN_NAME,
            route = { id = route2.id },
            config = {
              api_specification = spec_content,
              included_status_codes = { 400, 409 }
            },
          }

          local route3 = db.routes:insert({
            hosts = { "mocking-include-base-path.com" },
            service = service,
          })
          db.plugins:insert {
            name = PLUGIN_NAME,
            route = { id = route3.id },
            config = {
              api_specification = spec_content,
              include_base_path = true
            },
          }

          -- start kong
          assert(helpers.start_kong({
            database = db_strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            plugins = "bundled," .. PLUGIN_NAME,
          }))
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true)
        end)

        before_each(function()
          client = helpers.proxy_client()
        end)

        after_each(function()
          if client then
            client:close()
          end
        end)

        describe("OpenAPI 3.0 tests", function()
          it("/inventory GET", function()
            local res = assert(client:send {
              method = "GET",
              path = "/inventory",
              headers = {
                host = "mocking.com"
              }
            })

            assert.response(res).has.status(200)
            assert.equal("true", assert.response(res).has.header("X-Kong-Mocking-Plugin"))
            assert.equal("application/json", assert.response(res).has.header("Content-Type"))
            local body = assert.response(res).has.jsonbody()
            assert.same({
              id = "d290f1ee-6c54-4b01-90e6-d701748f0851",
              name = "test",
              release_date = "2016-08-29T09:12:33.001Z",
              manufacturer = {
                name = "ACME Corporation",
                home_page = "https://www.acme-corp.com",
                phone = "408-867-5309"
              }
            }, body)
          end)

          it("404 for non exist path", function()
            local res = assert(client:send {
              method = "GET",
              path = "/not_exist",
              headers = {
                host = "mocking.com"
              }
            })
            assert.response(res).has.status(404)
            local body = assert.response(res).has.jsonbody()
            assert.same("Corresponding path and method spec does not exist in API Specification", body.message)
          end)

          it("dot character in path", function()
            local res = assert(client:send {
              method = "GET",
              path = "/inventory.v2",
              headers = {
                host = "mocking.com"
              }
            })
            assert.response(res).has.status(200)
            assert.equal("true", assert.response(res).has.header("X-Kong-Mocking-Plugin"))
            assert.equal("application/json", assert.response(res).has.header("Content-Type"))
            local body = assert.response(res).has.jsonbody()
            assert.same({ id = "d290f1ee-6c54-4b01-90e6-d701748f0851" }, body)
          end)

          it("should return 400", function()
            local res = assert(client:send {
              method = "POST",
              path = "/inventory",
              headers = {
                host = "mocking-codes.com"
              }
            })

            assert.response(res).has.status(400)
          end)

          describe("include_base_path = true", function()
            it("/v1/inventory GET", function()
              local res = assert(client:send {
                method = "GET",
                path = "/v1/inventory",
                headers = {
                  host = "mocking-include-base-path.com"
                }
              })

              assert.response(res).has.status(200)
              assert.equal("true", assert.response(res).has.header("X-Kong-Mocking-Plugin"))
              assert.equal("application/json", assert.response(res).has.header("Content-Type"))
              local body = assert.response(res).has.jsonbody()
              assert.same({
                id = "d290f1ee-6c54-4b01-90e6-d701748f0851",
                name = "test",
                release_date = "2016-08-29T09:12:33.001Z",
                manufacturer = {
                  name = "ACME Corporation",
                  home_page = "https://www.acme-corp.com",
                  phone = "408-867-5309"
                }
              }, body)
            end)
          end)
        end)

        describe("Accept header match tests", function()
          it("simple accept header test case", function()
            local res = assert(client:send {
              method = "GET",
              path = "/inventory",
              headers = {
                host = "mocking.com",
                accept = "application/xml"
              }
            })

            assert.equal("application/xml", assert.response(res).has.header("Content-Type"))
          end)
          it("wildcard accept header test case", function()
            local res = assert(client:send {
              method = "GET",
              path = "/inventory",
              headers = {
                host = "mocking.com",
                accept = "text/*"
              }
            })

            local body = assert.res_status(200, res)
            assert.truthy(string.find(assert.response(res).has.header("Content-Type"), "text/html"))
            assert.equal('<html><body><p>Hello, world!</p></body></html>', body)
          end)

          it("quality value test case", function()
            local res = assert(client:send {
              method = "GET",
              path = "/inventory",
              headers = {
                host = "mocking.com",
                accept = "application/xml;q=0.1, text/html;q=0.5"
              }
            })

            local body = assert.res_status(200, res)
            assert.truthy(string.find(assert.response(res).has.header("Content-Type"), "text/html"))
            assert.same(body, '<html><body><p>Hello, world!</p></body></html>')
          end)
        end)

        describe("priority of examples and example", function()
          it("The priority of example should higher than examples", function()
            local res = assert(client:send {
              method = "GET",
              path = "/inventory",
              headers = {
                host = "mocking.com",
                accept = "text/html"
              }
            })

            local body = assert.res_status(200, res)
            assert.truthy(string.find(assert.response(res).has.header("Content-Type"), "text/html"))
            assert.same('<html><body><p>Hello, world!</p></body></html>', body)
          end)
        end)

        describe("abnormal tests", function()
          it("should return 404 for empty responses", function()
            local res = assert(client:send {
              method = "GET",
              path = "/inventory_empty_responses",
              headers = {
                host = "mocking.com"
              }
            })

            assert.response(res).has.status(404)
            local body = assert.response(res).has.jsonbody()
            assert.same({ message = "No examples exist in API specification for this resource matching Accept Header (application/json)" }, body)
          end)

          it("should return 200 for not content", function()
            local res = assert(client:send {
              method = "GET",
              path = "/inventory_without_content",
              headers = {
                host = "mocking.com"
              }
            })
            assert.response(res).has.status(200)
          end)

          it("should return 200 for empty content", function()
            local res = assert(client:send {
              method = "GET",
              path = "/inventory_empty_content",
              headers = {
                host = "mocking.com"
              }
            })
            assert.response(res).has.status(200)
          end)

          it("should return 200 for empty content examples", function()
            local res = assert(client:send {
              method = "GET",
              path = "/inventory_empty_content_examples",
              headers = {
                host = "mocking.com"
              }
            })
            assert.response(res).has.status(200)
          end)
        end)

        describe("behavioral headers", function()

          describe("X-Kong-Mocking-Delay", function()

            it("should delay 500ms", function()
              local s = ngx.now()
              local res = assert(client:send {
                method = "GET",
                path = "/inventory",
                headers = {
                  host = "mocking.com",
                  ["X-Kong-Mocking-Delay"] = "500"
                }
              })
              local elapsed = (ngx.now() - s) * 1000
              assert.response(res).has.status(200)
              assert.is_true(math.abs(elapsed - 500) <= 10)
            end)

            it("should return error", function()
              local res = assert(client:send {
                method = "GET",
                path = "/inventory",
                headers = {
                  host = "mocking.com",
                  ["X-Kong-Mocking-Delay"] = "10001"
                }
              })
              assert.response(res).has.status(400)
              local body = assert.response(res).has.jsonbody()
              assert.same({ message = "Invalid value for X-Kong-Mocking-Delay. The delay value should be a number between 0 and 10000" }, body)

              local res = assert(client:send {
                method = "GET",
                path = "/inventory",
                headers = {
                  host = "mocking.com",
                  ["X-Kong-Mocking-Delay"] = "-1"
                }
              })
              assert.response(res).has.status(400)
              local body = assert.response(res).has.jsonbody()
              assert.same({ message = "Invalid value for X-Kong-Mocking-Delay. The delay value should be a number between 0 and 10000" }, body)
            end)
          end)

          describe("X-Kong-Mocking-Example-Id", function()
            it("should respond particular example id", function()
              local res = assert(client:send {
                method = "GET",
                path = "/inventory",
                headers = {
                  host = "mocking.com",
                  accept = "application/xml",
                  ["X-Kong-Mocking-Example-Id"] = "1"
                }
              })
              assert.response(res).has.status(200)
              assert.equal("<id>1</id>", res:read_body())

              local res = assert(client:send {
                method = "GET",
                path = "/inventory",
                headers = {
                  host = "mocking.com",
                  accept = "application/xml",
                  ["X-Kong-Mocking-Example-Id"] = "2"
                }
              })
              assert.response(res).has.status(200)
              assert.equal("<id>2</id>", res:read_body())

              local res = assert(client:send {
                method = "GET",
                path = "/inventory",
                headers = {
                  host = "mocking.com",
                  accept = "application/xml",
                  ["X-Kong-Mocking-Example-Id"] = "three"
                }
              })
              assert.response(res).has.status(200)
              assert.equal("<id>three</id>", res:read_body())
            end)

            it("should return error", function()
              local res = assert(client:send {
                method = "GET",
                path = "/inventory",
                headers = {
                  host = "mocking.com",
                  accept = "application/xml",
                  ["X-Kong-Mocking-Example-Id"] = "inexistent"
                }
              })
              assert.response(res).has.status(400)
              local body = assert.response(res).has.jsonbody()
              assert.same({ message = "could not find the example id 'inexistent'" }, body)
            end)
          end)

          describe("X-Kong-Mocking-Status-Code", function()
            it("should respond particular status code", function()
              local res = assert(client:send {
                method = "GET",
                path = "/inventory",
                headers = {
                  host = "mocking.com",
                  accept = "text/plain",
                  ["X-Kong-Mocking-Status-Code"] = "400"
                }
              })
              assert.response(res).has.status(400)
              assert.equal("Hello, world!", res:read_body())
            end)

            it("should return error", function()
              local res = assert(client:send {
                method = "GET",
                path = "/inventory",
                headers = {
                  host = "mocking.com",
                  ["X-Kong-Mocking-Status-Code"] = "1"
                }
              })
              assert.response(res).has.status(400)
              local body = assert.response(res).has.jsonbody()
              assert.same({ message = "could not find the status code '1'" }, body)
            end)
          end)
        end)

        describe("Referenced schema tests", function()
          it("should return dereferenced schema", function()
            local res = assert(client:send {
              method = "GET",
              path = "/ref/inventory_ref_schema",
              headers = {
                host = "mocking.com"
              }
            })
            assert.response(res).has.status(200)
            local body = assert.response(res).has.jsonbody()

            local ok, err = structure_like({
              code = "SUCCESS",
              msg = "string",
              data = {
                id = "d290f1ee-6c54-4b01-90e6-d701748f0851",
                name = "string",
                releaseDate = "2022-09-14T08:47:16.316Z",
                manufacturer = {
                  name = "ACME Corporation",
                  homePage = "https://www.acme-corp.com",
                  phone = "408-867-5309",
                }
              }
            }, body)
            assert.is_nil(err)
            assert.is_true(ok)

            local res = assert(client:send {
              method = "GET",
              path = "/ref/inventory_ref_response",
              headers = {
                host = "mocking.com"
              }
            })
            assert.response(res).has.status(400)
            local body = assert.response(res).has.jsonbody()
            assert.same({
              code = "INVALID_REQUEST",
              msg = "Invalid Request",
            }, body)
          end)
        end)
      end)
    end
  end)
end
