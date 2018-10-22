local helpers    = require "spec.helpers"
local cjson      = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Admin API - Open API Spec routes - " .. strategy, function()
    local client
    local dao

    setup(function()
      _, _, dao = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database = strategy,
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    describe("/oas-config", function()
      describe("POST", function()
        describe("Error Handling", function()

          before_each(function()
            dao:truncate_tables()
            client = assert(helpers.admin_client())
          end)

          after_each(function()
            if client then client:close() end
          end)

          it("should return 400 if spec if not passed", function()
            local res = assert(client:send {
              method = "POST",
              path = "/oas-config",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "spec is required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if spec is not a str", function()
            local res = assert(client:send {
              method = "POST",
              path = "/oas-config",
              body = {
                spec = {}
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "spec is required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if spec is not valid json str", function()
            local res = assert(client:send {
              method = "POST",
              path = "/oas-config",
              body = {
                spec = "{derp"
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "Failed to convert spec to table 2:1: did not find expected ',' or '}'",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if spec is not valid yaml str", function()
            local res = assert(client:send {
              method = "POST",
              path = "/oas-config",
              body = {
                spec = "derp: [derp"
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "Failed to convert spec to table 1:8: did not find expected ',' or ']'",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if spec is not valid yaml str", function()
            local res = assert(client:send {
              method = "POST",
              path = "/oas-config",
              body = {
                spec = "derp: [derp"
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "Failed to convert spec to table 1:8: did not find expected ',' or ']'",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if missing host - JSON, v2", function()
            local f = assert(io.open("spec-ee/fixtures/oas_config/missing_host_v2.json"))
            local str = f:read("*a")
            f:close()

            local res = assert(client:send {
              method = "POST",
              path = "/oas-config",
              body = {
                spec = str
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "OAS v2 - host required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if servers are missing - JSON, v3", function()
            local f = assert(io.open("spec-ee/fixtures/oas_config/missing_servers_v3.json"))
            local str = f:read("*a")
            f:close()

            local res = assert(client:send {
              method = "POST",
              path = "/oas-config",
              body = {
                spec = str
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "OAS v3 - servers required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if missing host - YAML, v2", function()
            local f = assert(io.open("spec-ee/fixtures/oas_config/missing_host_v2.yaml"))
            local str = f:read("*a")
            f:close()

            local res = assert(client:send {
              method = "POST",
              path = "/oas-config",
              body = {
                spec = str
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "OAS v2 - host required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if missing host - YAML, v3", function()
            local f = assert(io.open("spec-ee/fixtures/oas_config/missing_servers_v3.yaml"))
            local str = f:read("*a")
            f:close()

            local res = assert(client:send {
              method = "POST",
              path = "/oas-config",
              body = {
                spec = str
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "OAS v3 - servers required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)
        end)

        describe("Success", function()
          local versions = {"v2", "v3"}
          local formats  = {"json", "yaml"}

          for _, version in ipairs(versions) do
            for _, format in ipairs(formats) do
              describe("Version: " .. version .. " Format: " .. format, function()
                local resp_body_json
                local file_path = "spec-ee/fixtures/oas_config/petstore_" .. version .. "." .. format

                setup(function()
                  client = assert(helpers.admin_client())
                  local f = assert(io.open(file_path))
                  local str = f:read("*a")
                  f:close()

                  local res = assert(client:send {
                    method = "POST",
                    path = "/oas-config",
                    body = {
                      spec = str
                    },
                    headers = {
                      ["Content-Type"] = "application/json",
                    }
                  })

                  local body = assert.res_status(201, res)
                  resp_body_json = cjson.decode(body)


                  if client then client:close() end
                end)

                teardown(function()
                  dao:truncate_tables()
                end)

                it("should generate 2 services and 4 routes", function()
                  table.sort(resp_body_json.services, function(a, b)
                    return a.name < b.name
                  end)

                  table.sort(resp_body_json.routes, function(a, b)
                    return a.protocols[1] .. a.paths[1] < b.protocols[1] .. b.paths[1]
                  end)

                  local expected_service = {
                    {
                      host = "petstore.swagger.io",
                      protocol = "http",
                      name = "swagger-petstore-1",
                      path = "/yeeee",
                      port = 9999,
                    },
                    {
                      host = "petstore.swagger.io",
                      protocol = "https",
                      name = "swagger-petstore-1-secure",
                      path = "/yeeee",
                      port = 9999,
                    }
                  }

                  assert.equal(2, #resp_body_json.services)

                  for id, service in ipairs(resp_body_json.services) do
                    assert.same(expected_service[id].host, service.host)
                    assert.same(expected_service[id].protocol, service.protocol)
                    assert.same(expected_service[id].name, service.name)
                    assert.same(expected_service[id].path, service.path)
                    assert.same(expected_service[id].port, service.port)
                  end

                  local expected_routes = {
                    {
                      methods = {"POST", "GET"},
                      paths = {"/pets"},
                      protocols = {"http"}
                    },
                    {
                      methods = {"GET"},
                      paths = {"/pets/(?<petId>\\S+)"},
                      protocols = {"http"}
                    },
                    {
                      methods = {"POST", "GET"},
                      paths = {"/pets"},
                      protocols = {"https"}
                    },
                    {
                      methods = {"GET"},
                      paths = {"/pets/(?<petId>\\S+)"},
                      protocols = {"https"}
                    },
                  }

                  assert.equal(4, #resp_body_json.routes)

                  for id, route in ipairs(resp_body_json.routes) do
                    assert.same(expected_routes[id].methods, route.methods)
                    assert.same(expected_routes[id].paths, route.paths)
                    assert.same(expected_routes[id].protocols, route.protocols)
                  end
                end)
              end)
            end
          end
        end)
      end)

      describe("PATCH", function()
        describe("Error Handling", function()

          before_each(function()
            dao:truncate_tables()
            client = assert(helpers.admin_client())
          end)

          after_each(function()
            if client then client:close() end
          end)

          it("should return 400 if spec if not passed", function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/oas-config",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "spec is required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if spec is not a str", function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/oas-config",
              body = {
                spec = {}
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "spec is required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if spec is not valid json str", function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/oas-config",
              body = {
                spec = "{derp"
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "Failed to convert spec to table 2:1: did not find expected ',' or '}'",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if spec is not valid yaml str", function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/oas-config",
              body = {
                spec = "derp: [derp"
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "Failed to convert spec to table 1:8: did not find expected ',' or ']'",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if spec is not valid yaml str", function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/oas-config",
              body = {
                spec = "derp: [derp"
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "Failed to convert spec to table 1:8: did not find expected ',' or ']'",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if missing host - JSON, v2", function()
            local f = assert(io.open("spec-ee/fixtures/oas_config/missing_host_v2.json"))
            local str = f:read("*a")
            f:close()

            local res = assert(client:send {
              method = "PATCH",
              path = "/oas-config",
              body = {
                spec = str
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "OAS v2 - host required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if servers are missing - JSON, v3", function()
            local f = assert(io.open("spec-ee/fixtures/oas_config/missing_servers_v3.json"))
            local str = f:read("*a")
            f:close()

            local res = assert(client:send {
              method = "PATCH",
              path = "/oas-config",
              body = {
                spec = str
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "OAS v3 - servers required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if missing host - YAML, v2", function()
            local f = assert(io.open("spec-ee/fixtures/oas_config/missing_host_v2.yaml"))
            local str = f:read("*a")
            f:close()

            local res = assert(client:send {
              method = "PATCH",
              path = "/oas-config",
              body = {
                spec = str
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "OAS v2 - host required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)

          it("should return 400 if missing host - YAML, v3", function()
            local f = assert(io.open("spec-ee/fixtures/oas_config/missing_servers_v3.yaml"))
            local str = f:read("*a")
            f:close()

            local res = assert(client:send {
              method = "PATCH",
              path = "/oas-config",
              body = {
                spec = str
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local expected = {
              message = "OAS v3 - servers required",
            }

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.same(expected, resp_body_json)
          end)
        end)

        describe("Success", function()
          local versions = {"v2", "v3"}
          local formats  = {"json", "yaml"}

          for _, version in ipairs(versions) do
            for _, format in ipairs(formats) do
              describe("Version: " .. version .. " Format: " .. format, function()
                local original_resp_body_json
                local resp_body_json
                local file_path = "spec-ee/fixtures/oas_config/petstore_" .. version .. "." .. format

                setup(function()
                  client = assert(helpers.admin_client())
                  local f = assert(io.open(file_path))
                  local str = f:read("*a")
                  f:close()

                  local res = assert(client:send {
                    method = "POST",
                    path = "/oas-config",
                    body = {
                      spec = str
                    },
                    headers = {
                      ["Content-Type"] = "application/json",
                    }
                  })

                  local body = assert.res_status(201, res)
                  original_resp_body_json = cjson.decode(body)

                  table.sort(original_resp_body_json.services, function(a, b)
                    return a.name < b.name
                  end)

                  table.sort(original_resp_body_json.routes, function(a, b)
                    return a.protocols[1] .. a.paths[1] < b.protocols[1] .. b.paths[1]
                  end)

                  local expected_service = {
                    {
                      host = "petstore.swagger.io",
                      protocol = "http",
                      name = "swagger-petstore-1",
                      path = "/yeeee",
                      port = 9999,
                    },
                    {
                      host = "petstore.swagger.io",
                      protocol = "https",
                      name = "swagger-petstore-1-secure",
                      path = "/yeeee",
                      port = 9999,
                    }
                  }

                  assert.equal(2, #original_resp_body_json.services)
                  assert.equal(4, #original_resp_body_json.routes)

                  for id, service in ipairs(original_resp_body_json.services) do
                    assert.same(expected_service[id].host, service.host)
                    assert.same(expected_service[id].protocol, service.protocol)
                    assert.same(expected_service[id].name, service.name)
                    assert.same(expected_service[id].path, service.path)
                    assert.same(expected_service[id].port, service.port)
                  end


                  local patch_file_path = "spec-ee/fixtures/oas_config/petstore_" .. version .. "_service_patch." .. format
                  local f = assert(io.open(patch_file_path))
                  local str = f:read("*a")
                  f:close()

                  local res = assert(client:send {
                    method = "PATCH",
                    path = "/oas-config",
                    body = {
                      spec = str
                    },
                    headers = {
                      ["Content-Type"] = "application/json",
                    }
                  })

                  local body = assert.res_status(200, res)
                  resp_body_json = cjson.decode(body)

                  table.sort(resp_body_json.services, function(a, b)
                    return a.name < b.name
                  end)

                  if client then client:close() end
                end)

                teardown(function()
                  dao:truncate_tables()
                end)

                it("should update existing services (host, port and path change) but not update routes", function()
                  local expected_service = {
                    {
                      host = "new.swagger.io",
                      protocol = "http",
                      name = "swagger-petstore-1",
                      path = "/wooo",
                      port = 8000
                    },
                    {
                      host = "new.swagger.io",
                      protocol = "https",
                      name = "swagger-petstore-1-secure",
                      path = "/wooo",
                      port = 8000
                    }
                  }

                  assert.equal(2, #resp_body_json.services)
                  assert.is_nil(resp_body_json.routes)

                  for id, service in ipairs(resp_body_json.services) do
                    assert.same(expected_service[id].host, service.host)
                    assert.same(expected_service[id].protocol, service.protocol)
                    assert.same(expected_service[id].name, service.name)
                    assert.same(expected_service[id].path, service.path)
                    assert.same(expected_service[id].port, service.port)
                  end
                end)

                it("should delete and remake routes if 'recreate_routes' param is passed", function()
                  client = assert(helpers.admin_client())
                  local patch_file_path = "spec-ee/fixtures/oas_config/petstore_" .. version .. "_service_patch." .. format
                  local f = assert(io.open(patch_file_path))
                  local str = f:read("*a")
                  f:close()

                  local res = assert(client:send {
                    method = "PATCH",
                    path = "/oas-config",
                    body = {
                      spec = str,
                      recreate_routes = true,
                    },
                    headers = {
                      ["Content-Type"] = "application/json",
                    }
                  })

                  local body = assert.res_status(201, res)
                  resp_body_json = cjson.decode(body)


                  table.sort(resp_body_json.routes, function(a, b)
                    return a.protocols[1] .. a.paths[1] < b.protocols[1] .. b.paths[1]
                  end)

                  if client then client:close() end

                  local expected_routes = {
                    {
                      methods = {"POST", "GET"},
                      paths = {"/pets"},
                      protocols = {"http"}
                    },
                    {
                      methods = {"GET"},
                      paths = {"/pets/(?<petId>\\S+)"},
                      protocols = {"http"}
                    },
                    {
                      methods = {"POST", "GET"},
                      paths = {"/pets"},
                      protocols = {"https"}
                    },
                    {
                      methods = {"GET"},
                      paths = {"/pets/(?<petId>\\S+)"},
                      protocols = {"https"}
                    },
                  }

                  assert.equal(4, #resp_body_json.routes)

                  for id, route in ipairs(resp_body_json.routes) do
                    assert.same(expected_routes[id].methods, route.methods)
                    assert.same(expected_routes[id].paths, route.paths)
                    assert.same(expected_routes[id].protocols, route.protocols)
                  end
                end)
              end)
            end
          end
        end)
      end)
    end)
  end)
end
