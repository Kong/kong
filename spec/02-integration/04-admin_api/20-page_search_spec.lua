-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local pl_stringx = require "pl.stringx"
local fmt = string.format

local strategy = "postgres"

describe("Admin API - search", function()

  describe("/entities search with DB: #" .. strategy, function()
    local client, bp, db

    local test_entity_count = 100
    local enabled_services_count = 80

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "consumers",
        "vaults",
        "workspaces",
        }, nil, {
        "env"
      })

      for i = 1, test_entity_count do
        local service = {
          name = fmt("service%s", i),
          enabled = i <= enabled_services_count,
          protocol = "http",
          host = fmt("example-%s.com", i),
          path = fmt("/%s", i),
          port = 15000 + i
        }
        local service, err, err_t = bp.services:insert(service)
        assert.is_nil(err)
        assert.is_nil(err_t)

        local route = {
          name = fmt("route%s", i),
          hosts = { fmt("example-%s.com", i) },
          paths = { fmt("/%s", i) },
          service = { name = fmt("service%s", i) }
        }
        local _, err, err_t = bp.routes:insert(route)
        assert.is_nil(err)
        assert.is_nil(err_t)

        local plugin = {
          name = "cors",
          instance_name = fmt("plugin%s", i),
          enabled = true,
          config = {},
          service = service,
        }
        local _, err, err_t = bp.plugins:insert(plugin)
        assert.is_nil(err)
        assert.is_nil(err_t)

        local vault = {
          name = "env",
          prefix = fmt("env-%s", i),
          description = fmt("description-%s", i)
        }
        local _, err, err_t = bp.vaults:insert(vault)
        assert.is_nil(err)
        assert.is_nil(err_t)

        local _, err, err_t = bp.workspaces:insert { name = "workspace-" .. i }
        assert.is_nil(err)
        assert.is_nil(err_t)

      end

      local consumers = {
        {
          username = "foo",
          custom_id = "bar",
        },
        {
          username = "foo2",
          custom_id = "bar2",
        },
        {
          username = "foo3",
          custom_id = "bar3",
        }
      }
      for _, consumer in pairs(consumers) do
        local _, err, err_t = bp.consumers:insert(consumer)
        assert.is_nil(err)
        assert.is_nil(err_t)
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

    describe("known field only - security check", function()
      describe("when quering for unknown field", function()
        it("returns error", function()
          local _, err = db.services:page(nil, nil, { search_fields = { wat = { eq = "wat" } } })
          assert.same(err, "[postgres] invalid option (search_fields: cannot search on unindexed field 'wat')")
        end)
      end)

      describe("when field name is not safe", function()
        it("returns error", function()
          local _, err = db.services:page(nil, nil, { search_fields = { ["name;drop/**/table/**/services;/**/--/**/-"] = { eq = "1" } } })
          assert.same(err, "[postgres] invalid option (search_fields: cannot search on unindexed field 'name;drop/**/table/**/services;/**/--/**/-')")
        end)
      end)
    end)

    describe("when searching for string field - (not uuid)", function()
      describe("when querying services by name", function()
        describe("with default sorting", function()
          it("runs fuzzy search", function()
            local res = assert(client:send {
              method = "GET",
              path = "/services?name=100"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same('service100', json.data[1].name)
          end)

          describe("when running LHS brackets on a string field", function()
            it("runs a lower than  query on string field", function()
              local res = client:get("/services",
                { query  = { ["name[lt]"] = "service3" }})
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              -- there are 23 services that have name lower than "service3"
              --   [
              -- (2)   service1, service2,
              -- (10)  service10, service11, ..., service19,
              -- (10)  service20, service21, ..., service29,
              -- (1)   service100
              -- ==== 23 ]
              assert.same(23, #json.data)
            end)
          end)
        end)

        describe("with custom sorting", function()
          it("runs fuzzy search", function()
            local res = assert(client:send {
              method = "GET",
              path = "/services?size=100&sort_by=name&name="
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(test_entity_count, #json.data)
            assert.same('service1', json.data[1].name)
          end)
        end)
      end)

      describe("when querying routes by name", function()
        describe("with default sorting", function()
          it("runs fuzzy search", function()
            local res = assert(client:send {
              method = "GET",
              path = "/routes?name=100"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same('route100', json.data[1].name)
          end)
        end)

        describe("with custom sorting", function()
          it("runs fuzzy search", function()
            local res = assert(client:send {
              method = "GET",
              path = "/routes?size=100&sort_by=name&name="
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(test_entity_count, #json.data)
            assert.same('route1', json.data[1].name)
          end)
        end)
      end)

      describe("when querying routes by hosts", function()
        it("runs fuzzy search", function()
          local res = assert(client:send {
            method = "GET",
            path = "/routes?hosts=100"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same("route100", json.data[1].name)
        end)
      end)

      describe("when querying vaults", function()
        describe("by name", function()
          it("runs fuzzy search", function()
            local res = assert(client:send {
              method = "GET",
              path = "/vaults?size=100&name=env"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(100, #json.data)
          end)
        end)

        describe("by prefix-env", function()
          it("runs fuzzy search", function()
            local res = assert(client:send {
              method = "GET",
              path = "/vaults?prefix=env-100"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same('env-100', json.data[1].prefix)
          end)
        end)
      end)

      describe("when querying workspaces", function()
        describe("when not searching but paging", function()
          describe("with default sorting", function()
            it("returns as much entites as possible per page as requested", function()
              local res = assert(client:send {
                method = "GET",
                path = "/workspaces?size=100"
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(100, #json.data)
            end)
          end)

          describe("with custom sorting", function()
            it("returns as much entites per page as requested", function()
              local res = assert(client:send {
                method = "GET",
                path = "/workspaces?size=200&sort_by=name"
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(101, #json.data)
              assert.same("workspace-1", json.data[2].name)
            end)
          end)
        end)

        describe("when searching", function()
          it("returns searched result", function()
            local res = assert(client:send {
              method = "GET",
              path = "/workspaces?name=workspace-100"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same('workspace-100', json.data[1].name)
          end)
        end)
      end)

      describe("when querying plugins by instance_name", function()
        it("runs fuzzy search", function()
          local res = assert(client:send {
            method = "GET",
            path = "/plugins?instance_name=plugin9"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(11, #json.data)
          for _, p in ipairs(json.data) do
            assert.is_true(pl_stringx.startswith(p.instance_name, "plugin9"))
          end
        end)
      end)
    end)

    describe("when searching by boolean field", function()
      describe("when doing exact search", function()
        it("returns only entites that match this field exactly", function()
          local res = assert(client:send {
            method = "GET",
            path = "/services?size=100&enabled=true"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(enabled_services_count, #json.data)

          local res = assert(client:send {
            method = "GET",
            path = "/services?size=100&enabled=false"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(test_entity_count - enabled_services_count, #json.data)
        end)
      end)

      describe("when trying LHS Brackets query", function()
        it("returns value that match query", function()
          local res = assert(client:send {
            method = "GET",
            path = "/services?size=100&enabled[lte]=true"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(test_entity_count, #json.data)

          local res = assert(client:send {
            method = "GET",
            path = "/services?size=100&enabled[lte]=false"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(test_entity_count - enabled_services_count, #json.data)
        end)
      end)
    end)

    describe("when searching by an array field", function()
      describe("when querying routes by protocol", function()
        it("returns those routes that contain this protocol", function()
          local res = assert(client:send {
            method = "GET",
            path = "/routes?protocols=http"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(100, #json.data)

          res = assert(client:send {
            method = "GET",
            path = "/routes?protocols=https"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(100, #json.data)

          res = assert(client:send {
            method = "GET",
            path = "/routes?protocols=http,https"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(100, #json.data)
        end)

        it("returns empty rresult when trying to run LHS brackets [lt] or [gt] on array field", function()
          local res = assert(client:send {
            method = "GET",
            path = "/routes?protocols[gt]=http,https"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(0, #json.data)

          local res = assert(client:send {
            method = "GET",
            path = "/routes?protocols[lt]=http,https"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(0, #json.data)
        end)

        it("returns matching routes when running LHS brackets [lte] or [gte] on array field", function()
          local res = assert(client:send {
            method = "GET",
            path = "/routes?protocols[gte]=http,https"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(100, #json.data)

          local res = assert(client:send {
            method = "GET",
            path = "/routes?protocols[lte]=http,https"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(100, #json.data)

          -- combination
          local res = assert(client:send {
            method = "GET",
            path = "/routes?protocols[lte]=http,https&protocols[gte]=http,https"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(100, #json.data)
        end)

        it("returns empty result if not routes contain requested protocols", function()
          local res = assert(client:send {
            method = "GET",
            path = "/routes?protocols=http,https,grpc"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(0, #json.data)
        end)

        describe("when combining operators", function()
          describe("with different operators family (like gt & lt)", function()
            it("returns result on [lte] & [gte]", function()
              local res = assert(client:send {
                method = "GET",
                path = "/routes?protocols[lte]=http,https&protocols[gte]=http,https"
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(100, #json.data)
            end)

            it("returns empty result on [lt] & [gt]", function()
              local res = assert(client:send {
                method = "GET",
                path = "/routes?protocols[lt]=http,https&protocols[gt]=http,https"
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(0, #json.data)
            end)
          end)

          describe("with same operator family (like lt & lte)", function()
            it("returns empty result on [lt] & [lte] - order does not matter (first lt)", function()
              local res = assert(client:send {
                method = "GET",
                path = "/routes?protocols[lt]=http,https&protocols[lte]=http,https"
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(0, #json.data)
            end)

            it("returns empty result on [lt] & [lte] - order does not matter (first lte)", function()
              local res = assert(client:send {
                method = "GET",
                path = "/routes?protocols[lte]=http,https&protocols[lt]=http,https"
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(0, #json.data)
            end)
          end)
        end)
      end)
    end)

    -- consumers are overwriting searching logic a litle bit
    describe("when querying consumers", function()
      it("consumers multiple fields", function()
        -- searching by username goes through normal flow of search_fields
        -- since it's a string field is a fuzzy search
        local res
        res = assert(client:send {
          method = "GET",
          path = "/consumers?username=foo"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(3, #json.data)


        -- searching by custom_id escapes the regular flow of search_fields
        -- which would have perfrom a fuzzy search on custom_id. Instead it's using
        -- dao's select_by_custom_id which is doing an exact search
        -- therefore we don't see custom_id=bar3 in custom_id=bar query
        res = assert(client:send {
          method = "GET",
          path = "/consumers?custom_id=bar"
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.same(1, #json.data)
        assert.same("foo", json.data[1].username)

        res = assert(client:send {
          method = "GET",
          path = "/consumers?custom_id=bar3"
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.same(1, #json.data)
        assert.same("foo3", json.data[1].username)

        res = assert(client:send {
          method = "GET",
          path = "/consumers?username=error&custom_id=bar3"
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.same(0, #json.data)
      end)
    end)

    describe("when querying for number field", function()
      describe("when running an exact search", function()
        describe("when port matches", function()
          it("filters result by specific port - without operator (defaults to eq)", function()
            local res = client:get("/services",
              { query  = { port = 15003 }})
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(1, #json.data)
            assert.same(15003, json.data[1].port)
          end)

          it("filters result by specific port - with explicit eq operator", function()
            local res = client:get("/services",
              { query  = { ["port[eq]"] = 15003 }})
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(1, #json.data)
            assert.same(15003, json.data[1].port)
          end)
        end)

        describe("when port does not match", function()
          describe("when searching for a number", function()
            it("returns empty data array", function()
              local res = client:get("/services",
                { query  = { port = 16999 }})
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(0, #json.data)
            end)
          end)

          describe("when data type does not match", function()
            it("returns 400 bad request", function()
              local res = assert(client:send {
                method = "GET",
                path = "/services?port" -- results in `port = true`
              })

              local body = assert.res_status(400, res)
              local json = cjson.decode(body)
              assert.same({
                code = 20,
                message = "searching port='true' but expected value of number type",
                name = "invalid search query"
              }, json)
            end)
          end)
        end)
      end)

      describe("when running LHS Brackests query", function()
        it("LHS brackets [lt] - returns ports lower than <x>", function()
          local res = client:get("/services",
            { query  = { ["port[lt]"] = 15003 }})
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(2, #json.data)
        end)

        it("LHS brackets [lte] - returns ports lower than or equal to <x>", function()
          local res = client:get("/services",
            { query  = { ["port[lte]"] = 15003 }})
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(3, #json.data)
        end)

        it("LHS brackets [gt] - returns ports greater than <x>", function()
          local res = client:get("/services",
            { query  = { ["port[gt]"] = 15093 }})
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(7, #json.data)
        end)

        it("LHS brackets [gte] - returns ports greater than or equal to <x>", function()
          local res = client:get("/services",
            { query  = { ["port[gte]"] = 15093 }})
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(8, #json.data)
        end)

        it("LHS brackets combination - returns ports between <x> and <y> (inclusive both ends)", function()
          local res = client:get("/services",
            { query  = { ["port[gte]"] = 15004, ["port[lte]"] = 15006 }})
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(3, #json.data)
        end)

        it("LHS brackets combination - returns ports between <x> and <y> (inclusive one end)", function()
          local res = client:get("/services",
            { query  = { ["port[gt]"] = 15004, ["port[lte]"] = 15006 }})
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(2, #json.data)
        end)

        it("LHS brackets priority - prioritizes equals over ranges - returns exact search", function()
          local res = client:get("/services",
            { query  = { ["port[gte]"] = 15004, ["port[lte]"] = 15006, port = 15008 }})
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(1, #json.data)
          assert.same(15008, json.data[1].port)
        end)

        it("LHS brackets unknown operator - request fails with 400", function()
          local res = client:get("/services",
            { query  = { ["port[unknown]"] = 15004 }})
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            code = 20,
            message = "'unknown' is not a valid search operator",
            name = "invalid search query"
          }, json)
        end)

        it("LHS brackets incorrect operator - request fails with 400", function()
          local res = assert(client:send {
            method = "GET",
            path = "/services?port[lte]<15004"
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            code = 20,
            message = "'lte]<1500' is not a valid search operator",
            name = "invalid search query"
          }, json)
        end)

        it("LHS brackets incorrect data type - request fails with 400", function()
          local res = assert(client:send {
            method = "GET",
            path = "/services?port[lte]"
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            code = 20,
            message = "searching port[lte]='true' but expected value of number type",
            name = "invalid search query"
          }, json)
        end)
      end)
    end)
  end)
end)
