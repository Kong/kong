-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers     = require "spec.helpers"
local utils       = require "kong.tools.utils"
local postgres    = require "kong.vitals.postgres.strategy"
local cjson       = require "cjson"
local time        = ngx.time
local fmt         = string.format

local pl_file = require "pl.file"
local compare_no_order = require "pl.tablex".compare_no_order

-- unsets kong license env vars and returns a function to restore their values
-- on test teardown
--
-- replace distributions_constants.lua to mock a GA release distribution
local function setup_distribution()
  local kld = os.getenv("KONG_LICENSE_DATA")
  helpers.unsetenv("KONG_LICENSE_DATA")

  local klp = os.getenv("KONG_LICENSE_PATH")
  helpers.unsetenv("KONG_LICENSE_PATH")

  local tmp_filename = "/tmp/distributions_constants.lua"
  assert(helpers.file.copy("kong/enterprise_edition/distributions_constants.lua", tmp_filename, true))
  assert(helpers.file.copy("spec-ee/fixtures/mock_distributions_constants.lua", "kong/enterprise_edition/distributions_constants.lua", true))

  return function()
    if kld then
      helpers.setenv("KONG_LICENSE_DATA", kld)
    end

    if klp then
      helpers.setenv("KONG_LICENSE_PATH", klp)
    end

    if helpers.path.exists(tmp_filename) then
      -- restore and delete backup
      assert(helpers.file.copy(tmp_filename, "kong/enterprise_edition/distributions_constants.lua", true))
      assert(helpers.file.delete(tmp_filename))
    end
  end
end

for _, db_strategy in helpers.each_strategy() do
  describe("Admin API Vitals with #" .. db_strategy, function()
    local client, db, strategy, bp, connector

    local minute_start_at = time() - ( time() % 60 )
    local node_1 = "20426633-55dc-4050-89ef-2382c95a611e"
    local node_2 = "8374682f-17fd-42cb-b1dc-7694d6f65ba0"
    local node_3 = "20478633-55dc-4050-89ef-2382c95a611f"

    local stat_labels = {
      "cache_datastore_hits_total",
      "cache_datastore_misses_total",
      "latency_proxy_request_min_ms",
      "latency_proxy_request_max_ms",
      "latency_upstream_min_ms",
      "latency_upstream_max_ms",
      "requests_proxy_total",
      "latency_proxy_request_avg_ms",
      "latency_upstream_avg_ms",
    }

    local consumer_stat_labels = {
      "requests_consumer_total",
    }

    describe("when vitals is enabled", function()
      describe("in development package", function ()
        local kld

        setup(function()
          bp, db = helpers.get_db_utils(db_strategy)
          connector = db.connector

          kld = os.getenv("KONG_LICENSE_DATA")
          helpers.unsetenv("KONG_LICENSE_DATA")

          -- vitals only works with a valid license that matches the portal_and_vitals_key
          helpers.setenv("KONG_LICENSE_DATA", pl_file.read("spec-ee/fixtures/mock_license.json"))


          -- to insert test data
          if db.strategy == "postgres" then
            strategy = postgres.new(db)
            local q = "create table if not exists " .. strategy:current_table_name() ..
                "(LIKE vitals_stats_seconds INCLUDING defaults INCLUDING constraints INCLUDING indexes)"
            assert(connector:query(q))

            local node_q = "insert into vitals_node_meta(node_id, hostname) values('%s', '%s')"
            local nodes = { node_1, node_2, node_3 }

            for i, node in ipairs(nodes) do
              assert(connector:query(fmt(node_q, node, "testhostname" .. i)))
            end
          end

          local test_data_1 = {
            { minute_start_at, 0, 0, nil, nil, nil, nil, 0, 1, 10, 1, 10 },
            { minute_start_at + 1, 0, 3, 0, 11, 193, 212, 1, 1, 10, 1, 10 },
            { minute_start_at + 2, 3, 4, 1, 8, 60, 9182, 4, 1, 10, 1, 10 },
          }

          local test_data_2 = {
            { minute_start_at + 1, 1, 5, 0, 99, 25, 144, 9, 1, 10, 1, 10 },
            { minute_start_at + 2, 1, 7, 0, 0, 13, 19, 8, 1, 10, 1, 10 },
          }

          assert(strategy:insert_stats(test_data_1, node_1))
          assert(strategy:insert_stats(test_data_2, node_2))

          assert(helpers.start_kong({
            database = db_strategy,
            portal = true,
            portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
            vitals   = true,
          }))

          client = helpers.admin_client()
        end)

        teardown(function()
          if client then
            client:close()
          end

          helpers.stop_kong()

          if kld then
            helpers.setenv("KONG_LICENSE_DATA", kld)
          end
        end)

        describe("/vitals", function()
          describe("GET", function()
            it("returns data about vitals configuration", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals"
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                stats = {
                  cache_datastore_hits_total = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                      nodes = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  cache_datastore_misses_total = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                      nodes = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  latency_proxy_request_min_ms = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                      nodes = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  latency_proxy_request_max_ms = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                      nodes = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  latency_upstream_min_ms = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                      nodes = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  latency_upstream_max_ms = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                      nodes = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  requests_proxy_total = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                      nodes = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  requests_consumer_total = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                      nodes = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  latency_proxy_request_avg_ms = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                      nodes = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  latency_upstream_avg_ms = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                      nodes = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  status_code_classes_total = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  status_code_classes_per_workspace_total = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  status_codes_per_consumer_route_total = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  status_codes_per_consumer_total = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  status_codes_per_service_total = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                  status_codes_per_route_total = {
                    levels = {
                      cluster = {
                        intervals = {
                          seconds = { retention_period_seconds = 3600 },
                          minutes = { retention_period_seconds = 90000 },
                          days = { retention_period_seconds = 0 },
                        },
                      },
                    }
                  },
                }
              }
              assert.same(expected, json)
            end)
          end)
        end)

        describe("/vitals/nodes", function()
          describe("GET", function()
            it("fails intermittently -- retrieves the vitals seconds data for all nodes", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes",
                query = {
                  interval = "seconds"
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  level = "node",
                  interval = "seconds",
                  interval_width = 1,
                  earliest_ts = minute_start_at,
                  latest_ts = minute_start_at + 2,
                  stat_labels = stat_labels,
                  nodes = {
                    [node_1] = { hostname = "testhostname1" },
                    [node_2] = { hostname = "testhostname2" },
                  },
                },
                stats = {
                  ["20426633-55dc-4050-89ef-2382c95a611e"] = {
                    [tostring(minute_start_at)] = { 0, 0, cjson.null, cjson.null, cjson.null, cjson.null, 0, 10, 10 },
                    [tostring(minute_start_at + 1)] = { 0, 3, 0, 11, 193, 212, 1, 10, 10 },
                    [tostring(minute_start_at + 2)] = { 3, 4, 1, 8, 60, 9182, 4, 10, 10 },
                  },
                  ["8374682f-17fd-42cb-b1dc-7694d6f65ba0"] = {
                    [tostring(minute_start_at + 1)] = { 1, 5, 0, 99, 25, 144, 9, 10, 10 },
                    [tostring(minute_start_at + 2)] = { 1, 7, 0, 0, 13, 19, 8, 10, 10 },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("fails intermittently -- retrieves the vitals minutes data for all nodes", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes",
                query = {
                  interval = "minutes"
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  level = "node",
                  interval = "minutes",
                  interval_width = 60,
                  earliest_ts = minute_start_at,
                  latest_ts = minute_start_at,
                  stat_labels = stat_labels,
                  nodes = {
                    [node_1] = { hostname = "testhostname1" },
                    [node_2] = { hostname = "testhostname2" },
                  },
                },
                stats = {
                  [node_1] = {
                    [tostring(minute_start_at)] = { 3, 7, 0, 11, 60, 9182, 5, 10, 10 }
                  },
                  [node_2] = {
                    [tostring(minute_start_at)] = { 2, 12, 0, 99, 13, 144, 17, 10, 10 }
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("returns a 400 if called with invalid interval", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes",
                query = {
                  interval = "so-wrong"
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: interval must be 'days', 'minutes' or 'seconds'", json.message)
            end)

            it("returns a 400 if called with invalid start_ts", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes",
                query = {
                  interval = "seconds",
                  start_ts = "foo",
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: start_ts must be a number", json.message)
            end)
          end)
        end)

        describe("/vitals/nodes/{node_id}", function()
          describe("GET", function()
            it("retrieves the vitals seconds data for a requested node", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes/" .. node_1,
                query = {
                  interval = "seconds"
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  level = "node",
                  interval = "seconds",
                  interval_width = 1,
                  earliest_ts = minute_start_at,
                  latest_ts = minute_start_at + 2,
                  stat_labels = stat_labels,
                  nodes = {
                    [node_1] = { hostname = "testhostname1"}
                  }
                },
                stats = {
                  [node_1] = {
                    [tostring(minute_start_at)] = { 0, 0, cjson.null, cjson.null, cjson.null, cjson.null, 0, 10, 10 },
                    [tostring(minute_start_at + 1)] = { 0, 3, 0, 11, 193, 212, 1, 10, 10 },
                    [tostring(minute_start_at + 2)] = { 3, 4, 1, 8, 60, 9182, 4, 10, 10 },
                  },
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("retrieves the vitals minutes data for a requested node", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes/" .. node_1,
                query = {
                  interval = "minutes"
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                stats = {
                  [node_1] = {
                    [tostring(minute_start_at)] = { 3, 7, 0, 11, 60, 9182, 5, 10, 10 }
                  }
                },
                meta = {
                  level = "node",
                  interval = "minutes",
                  interval_width = 60,
                  earliest_ts = minute_start_at,
                  latest_ts = minute_start_at,
                  stat_labels = stat_labels,
                  nodes = {
                    [node_1] = { hostname = "testhostname1"}
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("returns empty stats if the requested node hasn't reported data", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes/" .. node_3,
                query = {
                  interval = "minutes"
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  level = "node",
                  interval = "minutes",
                  interval_width = 60,
                },
                stats = {},
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("returns a 400 if called with invalid interval", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes/" .. node_1,
                query = {
                  wrong_query_key = "seconds"
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: interval must be 'days', 'minutes' or 'seconds'", json.message)
            end)

            it("returns a 400 if called with invalid start_ts", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes/" .. node_1,
                query = {
                  interval = "seconds",
                  start_ts = "foo",
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: start_ts must be a number", json.message)
            end)

            it("returns a 404 if the node_id is not valid", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes/totally-fake-uuid",
                query = {
                  interval = "seconds"
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)

            it("returns a 404 if the node_id does not exist", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/nodes/" .. utils.uuid(),
                query = {
                  interval = "seconds"
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)
          end)
        end)

        describe("/vitals/cluster", function()
          describe("GET", function()
            --XXX EE: flaky
            pending("retrieves the vitals seconds cluster data", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/cluster",
                query = {
                  interval = "seconds"
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  level = "cluster",
                  interval = "seconds",
                  interval_width = 1,
                  earliest_ts = minute_start_at,
                  latest_ts = minute_start_at + 2,
                  stat_labels = stat_labels,
                },
                stats = {
                  cluster = {
                    [tostring(minute_start_at)] = { 0, 0, cjson.null, cjson.null, cjson.null, cjson.null, 0, 10, 10 },
                    [tostring(minute_start_at + 1)] = { 1, 8, 0, 99, 25, 212, 10, 10, 10 },
                    [tostring(minute_start_at + 2)] = { 4, 11, 0, 8, 13, 9182, 12, 10, 10 }
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            --XXX EE: flaky
            pending("retrieves the vitals minutes cluster data", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/cluster",
                query = {
                  interval = "minutes"
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  level = "cluster",
                  interval = "minutes",
                  interval_width = 60,
                  earliest_ts = minute_start_at,
                  latest_ts = minute_start_at,
                  stat_labels = stat_labels,
                },
                stats = {
                  cluster = {
                    [tostring(minute_start_at)] = { 5, 19, 0, 99, 13, 9182, 22, 10, 10 }
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("returns a 400 if called with invalid interval", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/cluster",
                query = {
                  interval = "so-wrong"
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: interval must be 'days', 'minutes' or 'seconds'", json.message)
            end)

            it("returns a 400 if called with invalid start_ts", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/cluster",
                query = {
                  interval = "minutes",
                  start_ts = "foo",
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: start_ts must be a number", json.message)
            end)
          end)
        end)

        describe("/vitals/status_code_classes (cluster)", function()
          before_each(function()
            db:truncate("vitals_code_classes_by_cluster")
          end)

          describe("GET", function()
            it("retrieves the seconds-level response code data for the cluster", function()
              local now = time()

              local test_status_code_class_data = {
                { 4, now - 1, 1, 10 },
                { 4, now, 1, 15 },
                { 5, now, 1, 20 },
              }

              assert(strategy:insert_status_code_classes(test_status_code_class_data))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_code_classes",
                query = {
                  interval = "seconds",
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  earliest_ts = now - 1,
                  interval    = "seconds",
                  latest_ts   = now,
                  level       = "cluster",
                  entity_type = "cluster",
                  stat_labels = {
                    "status_code_classes_total",
                  },
                  status_code_totals = {
                    ["4xx"] = 25,
                    ["5xx"] = 20,
                    ["total"] = 45,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(now - 1)] = {
                      ["4xx"] = 10,
                    },
                    [tostring(now)] = {
                      ["4xx"] = 15,
                      ["5xx"] = 20,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("retrieves the minutes-level response code data for the cluster", function()
              local minute_start_at = time() - (time() % 60)

              local test_status_code_class_data = {
                { 4, minute_start_at - 60, 60, 10 },
                { 4, minute_start_at, 60, 25 },
                { 5, minute_start_at, 60, 20 },
              }

              assert(strategy:insert_status_code_classes(test_status_code_class_data))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_code_classes",
                query = {
                  interval = "minutes",
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  earliest_ts = minute_start_at - 60,
                  interval    = "minutes",
                  latest_ts   = minute_start_at,
                  level       = "cluster",
                  entity_type = "cluster",
                  stat_labels = {
                    "status_code_classes_total",
                  },
                  status_code_totals = {
                    ["4xx"] = 35,
                    ["5xx"] = 20,
                    ["total"] = 55,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(minute_start_at - 60)] = {
                      ["4xx"] = 10,
                    },
                    [tostring(minute_start_at)] = {
                      ["4xx"] = 25,
                      ["5xx"] = 20,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)
          end)
        end)

        describe("/vitals/status_code_classes (workspace)", function()
          local workspace, workspace_id

          before_each(function()
            db:truncate("vitals_code_classes_by_workspace")

            workspace = db.workspaces:select_by_name("default")
            assert.not_nil(workspace)

            workspace_id = workspace.id
          end)

          describe("GET", function()
            it("retrieves the seconds-level status code classes for a given workspace", function()
              local now = time()

              assert(strategy:insert_status_code_classes_by_workspace({
                  { workspace_id, 4, now, 1, 101},
                  { workspace_id, 2, now - 1, 1, 205},
                  { workspace_id, 5, now - 1, 1, 6},
                }))

              local res = assert(client:send {
                method = "GET",
                path = "/default/vitals/status_code_classes",
                query = {
                  interval   = "seconds",
                }
              })

              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  entity_type = "workspace",
                  entity_id   = workspace_id,
                  earliest_ts = now - 1,
                  interval    = "seconds",
                  latest_ts   = now,
                  level       = "cluster",
                  stat_labels = {
                    "status_code_classes_per_workspace_total",
                  },
                  status_code_totals = {
                    ["2xx"] = 205,
                    ["4xx"] = 101,
                    ["5xx"] = 6,
                    ["total"] = 312,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(now - 1)] = {
                      ["2xx"] = 205,
                      ["5xx"] = 6,
                    },
                    [tostring(now)] = {
                      ["4xx"] = 101,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("retrieves the minutes-level response code data for a given workspace", function()
              local minute_start_at = time() - (time() % 60)

              assert(strategy:insert_status_code_classes_by_workspace({
                  { workspace_id, 4, minute_start_at, 60, 101},
                  { workspace_id, 2, minute_start_at - 60, 60, 205},
                  { workspace_id, 5, minute_start_at - 60, 60, 6},
                }))

              local res = assert(client:send {
                method = "GET",
                path = "/default/vitals/status_code_classes",
                query = {
                  interval   = "minutes",
                }
              })

              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  entity_type = "workspace",
                  entity_id   = workspace_id,
                  earliest_ts = minute_start_at - 60,
                  interval    = "minutes",
                  latest_ts   = minute_start_at,
                  level       = "cluster",
                  stat_labels = {
                    "status_code_classes_per_workspace_total",
                  },
                  status_code_totals = {
                    ["2xx"] = 205,
                    ["4xx"] = 101,
                    ["5xx"] = 6,
                    ["total"] = 312,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(minute_start_at - 60)] = {
                      ["2xx"] = 205,
                      ["5xx"] = 6,
                    },
                    [tostring(minute_start_at)] = {
                      ["4xx"] = 101,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("returns a 404 if called with invalid workspace_id", function()
              local res = assert(client:send {
                method = "GET",
                path = "/not-a-uuid/vitals/status_code_classes",
                query = {
                  interval = "minutes",
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Workspace 'not-a-uuid' not found", json.message)
            end)

            it("returns a 404 if called with a workspace_id that doesn't exist", function()
              local workspace_id = utils.uuid()
              local res = assert(client:send {
                method = "GET",
                path = "/" .. workspace_id .. "/vitals/status_code_classes",
                query = {
                  interval = "minutes",
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Workspace '".. workspace_id .. "' not found", json.message)
            end)
          end)
        end)

        describe("/vitals/status_code_classes - validations", function()
          it("returns a 400 if called with invalid interval", function()
            local res = assert(client:send {
              method = "GET",
              path = "/vitals/status_code_classes",
              query = {
                interval = "millenia",
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: interval must be 'days', 'minutes' or 'seconds'", json.message)
          end)

          it("returns a 400 if called with invalid start_ts", function()
            local res = assert(client:send {
              method = "GET",
              path = "/vitals/status_code_classes",
              query = {
                interval = "seconds",
                start_ts = "once, long ago",
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: start_ts must be a number", json.message)
          end)
        end)

        describe("/vitals/status_codes/by_service", function()
          local service, service_id

          before_each(function()
            db:truncate("vitals_codes_by_service")
            db:truncate("services")

            service = bp.services:insert()
            service_id = service.id
          end)

          describe("GET", function()
            it("retrieves the seconds-level response code data for a given service", function()
              local now = time()

              assert(strategy:insert_status_codes_by_route({
                { utils.uuid(), service_id, "404", now, 1, 101 },
                { utils.uuid(), service_id, "200", now - 1, 1, 205 },
                { utils.uuid(), service_id, "500", now - 1, 1, 6 },
              }))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_service",
                query = {
                  interval   = "seconds",
                  service_id = service_id,
                }
              })

              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  workspace_id = ngx.ctx.workspace,
                  entity_type = "service",
                  entity_id   = service_id,
                  earliest_ts = now - 1,
                  interval    = "seconds",
                  latest_ts   = now,
                  level       = "cluster",
                  stat_labels = {
                    "status_codes_per_service_total",
                  },
                  status_code_totals = {
                    ["200"] = 205,
                    ["404"] = 101,
                    ["500"] = 6,
                    ["total"] = 312,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(now - 1)] = {
                      ["200"] = 205,
                      ["500"] = 6,
                    },
                    [tostring(now)] = {
                      ["404"] = 101,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("retrieves the minutes-level response code data for a given service", function()
              local minute_start_at = time() - (time() % 60)

              assert(strategy:insert_status_codes_by_route({
                { utils.uuid(), service_id, "404", minute_start_at, 60, 101 },
                { utils.uuid(), service_id, "200", minute_start_at - 60, 60, 205 },
                { utils.uuid(), service_id, "500", minute_start_at - 60, 60, 6 },
              }))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_service",
                query = {
                  interval   = "minutes",
                  service_id = service_id,
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  workspace_id = ngx.ctx.workspace,
                  entity_type = "service",
                  entity_id   = service_id,
                  earliest_ts = minute_start_at - 60,
                  interval    = "minutes",
                  latest_ts   = minute_start_at,
                  level       = "cluster",
                  stat_labels = {
                    "status_codes_per_service_total",
                  },
                  status_code_totals = {
                    ["200"] = 205,
                    ["404"] = 101,
                    ["500"] = 6,
                    ["total"] = 312,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(minute_start_at - 60)] = {
                      ["200"] = 205,
                      ["500"] = 6,
                    },
                    [tostring(minute_start_at)] = {
                      ["404"] = 101,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("returns a 400 if called with invalid interval", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_service",
                query = {
                  interval   = "so-wrong",
                  service_id = service_id,
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: interval must be 'days', 'minutes' or 'seconds'", json.message)
            end)

            it("returns a 400 if called with invalid service_id", function()
              local service_id = "shh.. I'm not a real service id"
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_service",
                query = {
                  interval   = "minutes",
                  service_id = service_id,
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: service_id is invalid", json.message)
            end)

            it("returns a 400 if called with invalid start_ts", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_service",
                query = {
                  interval   = "seconds",
                  service_id = service_id,
                  start_ts   = "foo",
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: start_ts must be a number", json.message)
            end)

            it("returns a 404 if called with a service_id that doesn't exist", function()
              local service_id = "20426633-55dc-4050-89ef-2382c95a611e"
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_service",
                query = {
                  interval   = "minutes",
                  service_id = service_id,
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)

            it("returns a 404 if called with a workspace that doesn't exist", function()
              local res = assert(client:send {
                method = "GET",
                path = "/cats/vitals/status_codes/by_service",
                query = {
                  interval   = "minutes",
                  service_id = service_id,
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Workspace 'cats' not found", json.message)
            end)

            it("returns a 404 if called with a workspace where the service doesn't belong", function()
              local res = client:post("/workspaces", {
                headers = {
                  ["Content-Type"] = "application/json"
                },
                body    = {
                  name = "cats",
                }})
              assert.res_status(201, res)

              local res = assert(client:send {
                method = "GET",
                path = "/cats/vitals/status_codes/by_service",
                query = {
                  interval   = "minutes",
                  service_id = service_id,
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)

              assert.res_status(204, client:delete("/workspaces/cats"))
            end)
          end)
        end)

        describe("/vitals/status_codes/by_route", function()
          local route, route_id, route2, route2_id

          before_each(function()
            db:truncate("vitals_codes_by_route")
            db:truncate("routes")

            route = bp.routes:insert({ paths = { "/my-route" } })
            route_id = route.id

            route2 = bp.routes:insert({ paths = { "/my-route-2" } })
            route2_id = route2.id

          end)

          describe("GET", function()
            it("retrieves the seconds-level response code data for a given route", function()
              local now = time()
              local service_id = utils.uuid()

              local test_status_code_data = {
                { route_id, service_id, "404", tostring(now), "1", 101},
                { route_id, service_id, "200", tostring(now - 1), "1", 205},
                { route_id, service_id, "500", tostring(now - 1), "1", 6},
              }

              assert(strategy:insert_status_codes_by_route(test_status_code_data))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_route",
                query = {
                  interval = "seconds",
                  route_id = route_id,
                }
              })

              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  workspace_id = ngx.ctx.workspace,
                  entity_type = "route",
                  entity_id   = route_id,
                  earliest_ts = now - 1,
                  interval    = "seconds",
                  latest_ts   = now,
                  level       = "cluster",
                  stat_labels = {
                    "status_codes_per_route_total",
                  },
                  status_code_totals = {
                    ["200"] = 205,
                    ["404"] = 101,
                    ["500"] = 6,
                    ["total"] = 312,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(now - 1)] = {
                      ["200"] = 205,
                      ["500"] = 6,
                    },
                    [tostring(now)] = {
                      ["404"] = 101,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("retrieves the seconds-level response code data for a given serviceless route", function()
              local now = time()

              local test_status_code_data = {
                { route_id, "", "404", tostring(now), "1", 101},
                { route_id, "", "200", tostring(now - 1), "1", 205},
                { route_id, "", "500", tostring(now - 1), "1", 6},
              }

              assert(strategy:insert_status_codes_by_route(test_status_code_data))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_route",
                query = {
                  interval = "seconds",
                  route_id = route2_id,
                }
              })

              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  workspace_id = ngx.ctx.workspace,
                  entity_type = "route",
                  entity_id   = route2_id,
                  earliest_ts = now - 1,
                  interval    = "seconds",
                  latest_ts   = now,
                  level       = "cluster",
                  stat_labels = {
                    "status_codes_per_route_total",
                  },
                  status_code_totals = {
                    ["200"] = 205,
                    ["404"] = 101,
                    ["500"] = 6,
                    ["total"] = 312,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(now - 1)] = {
                      ["200"] = 205,
                      ["500"] = 6,
                    },
                    [tostring(now)] = {
                      ["404"] = 101,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("retrieves the minutes-level response code data for a given route", function()
              local minute_start_at = time() - (time() % 60)
              local service_id = utils.uuid()

              local test_status_code_data = {
                { route_id, service_id, "404", tostring(minute_start_at), "60", 101},
                { route_id, service_id, "200", tostring(minute_start_at - 60), "60", 205},
                { route_id, service_id, "500", tostring(minute_start_at - 60), "60", 6},
              }

              assert(strategy:insert_status_codes_by_route(test_status_code_data))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_route",
                query = {
                  interval = "minutes",
                  route_id = route_id,
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  workspace_id = ngx.ctx.workspace,
                  entity_type = "route",
                  entity_id   = route_id,
                  earliest_ts = minute_start_at - 60,
                  interval    = "minutes",
                  latest_ts   = minute_start_at,
                  level       = "cluster",
                  stat_labels = {
                    "status_codes_per_route_total",
                  },
                  status_code_totals = {
                    ["200"] = 205,
                    ["404"] = 101,
                    ["500"] = 6,
                    ["total"] = 312,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(minute_start_at - 60)] = {
                      ["200"] = 205,
                      ["500"] = 6,
                    },
                    [tostring(minute_start_at)] = {
                      ["404"] = 101,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("returns a 400 if called with invalid interval", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_route",
                query = {
                  interval = "so-wrong",
                  route_id = route_id,
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: interval must be 'days', 'minutes' or 'seconds'", json.message)
            end)

            it("returns a 400 if called with invalid route_id", function()
              local route_id = "shh.. I'm not a real route id"
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_route",
                query = {
                  interval = "minutes",
                  route_id = route_id,
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: route_id is invalid", json.message)
            end)

            it("returns a 400 if called with no route_id", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_route",
                query = {
                  interval = "minutes",
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: route_id is invalid", json.message)
            end)

            it("returns a 400 if called with invalid start_ts", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_route",
                query = {
                  interval = "seconds",
                  route_id = route_id,
                  start_ts = "foo",
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: start_ts must be a number", json.message)
            end)

            it("returns a 404 if called with a route_id that doesn't exist", function()
              local route_id = "20426633-55dc-4050-89ef-2382c95a611a"
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_route",
                query = {
                  interval = "minutes",
                  route_id = route_id,
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)

            it("returns a 404 if called with a workspace that doesn't exist", function()
              local res = assert(client:send {
                method = "GET",
                path = "/cats/vitals/status_codes/by_route",
                query = {
                  interval   = "minutes",
                  route_id = route_id,
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Workspace 'cats' not found", json.message)
            end)

            it("returns a 404 if called with a workspace where the route doesn't belong", function()
              local res = client:post("/workspaces", {
                headers = {
                  ["Content-Type"] = "application/json"
                },
                body    = {
                  name = "cats",
                }})
              assert.res_status(201, res)

              local res = assert(client:send {
                method = "GET",
                path = "/cats/vitals/status_codes/by_route",
                query = {
                  interval   = "minutes",
                  route_id = route_id,
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)

              assert.res_status(204, client:delete("/workspaces/cats"))
            end)
          end)
        end)

        describe("/vitals/status_codes/by_consumer", function()
          before_each(function()
            db:truncate("consumers")
            db:truncate("vitals_codes_by_consumer_route")
          end)

          describe("GET", function()
            it("retrieves the seconds-level response code data for a given consumer", function()
              local consumer = assert(bp.consumers:insert_ws({
                username  = "bob",
                custom_id = "1234"
              }, db.workspaces:select_by_name("default")))

              local now        = time()
              local minute     = now - (now % 60)
              local route_id   = utils.uuid()
              local service_id = utils.uuid()

              local test_status_code_data = {
                { consumer.id, route_id, service_id, "404", tostring(now), "1", 4 },
                { consumer.id, route_id, service_id, "404", tostring(now - 1), "1", 2 },
                { consumer.id, route_id, service_id, "500", tostring(minute), "60", 5 },
              }

              assert(strategy:insert_status_codes_by_consumer_and_route(test_status_code_data))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval    = "seconds",
                  consumer_id = consumer.id,
                }
              })

              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  entity_type = "consumer",
                  entity_id   = consumer.id,
                  earliest_ts = now - 1,
                  interval    = "seconds",
                  latest_ts   = now,
                  level       = "cluster",
                  stat_labels = {
                    "status_codes_per_consumer_total",
                  },
                  status_code_totals = {
                    ["404"] = 6,
                    ["total"] = 6,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(now - 1)] = {
                      ["404"] = 2,

                    },
                    [tostring(now)] = {
                      ["404"] = 4,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("retrieves the minutes-level response code data for a given consumer", function()
              local consumer = assert(bp.consumers:insert_ws({
                username  = "bob",
                custom_id = "1234"
              }, db.workspaces:select_by_name("default")))

              local minute_start_at = time() - (time() % 60)
              local route_id        = utils.uuid()
              local service_id      = utils.uuid()

              local test_status_code_data = {
                { consumer.id, route_id, service_id, "404", tostring(minute_start_at), "60", 101},
                { consumer.id, route_id, service_id, "200", tostring(minute_start_at - 60), "60", 205},
                { consumer.id, route_id, service_id, "500", tostring(minute_start_at - 60), "60", 6},
              }

              assert(strategy:insert_status_codes_by_consumer_and_route(test_status_code_data))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval = "minutes",
                  consumer_id = consumer.id,
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  entity_type = "consumer",
                  entity_id   = consumer.id,
                  earliest_ts = minute_start_at - 60,
                  interval    = "minutes",
                  latest_ts   = minute_start_at,
                  level       = "cluster",
                  stat_labels = {
                    "status_codes_per_consumer_total",
                  },
                  status_code_totals = {
                    ["200"] = 205,
                    ["404"] = 101,
                    ["500"] = 6,
                    ["total"] = 312,
                  },
                },
                stats = {
                  cluster = {
                    [tostring(minute_start_at - 60)] = {
                      ["200"] = 205,
                      ["500"] = 6,
                    },
                    [tostring(minute_start_at)] = {
                      ["404"] = 101,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("returns a 400 if called with invalid interval", function()
              local consumer = assert(bp.consumers:insert_ws({
                username  = "bob",
                custom_id = "1234"
              }, db.workspaces:select_by_name("default")))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval = "seconds",
                  consumer_id = consumer.id,
                  start_ts = "foo",
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: start_ts must be a number", json.message)
            end)

            it("returns a 400 if called with invalid start_ts", function()
              local consumer = assert(db.consumers:insert {
                username  = "bob",
                custom_id = "1234"
              })

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval = "seconds",
                  consumer_id = consumer.id,
                  start_ts = "foo",
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: start_ts must be a number", json.message)
            end)

            it("returns a 404 if called with invalid consumer_id", function()
              local consumer_id = "shh.. I'm not a real consumer id"
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval = "minutes",
                  consumer_id = consumer_id,
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)

            it("returns a 404 if called with no consumer_id", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval = "minutes",
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)

            it("returns a 404 if called with a consumer_id that is not an actual id for a consumer", function()
              local consumer_id = "20426633-55dc-4050-89ef-2382c95a611a"
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval = "minutes",
                  consumer_id = consumer_id,
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)
          end)
        end)

        describe("/vitals/status_codes/by_consumer_and_route", function()
          before_each(function()
            db:truncate("consumers")
            db:truncate("routes")
            db:truncate("vitals_codes_by_consumer_route")
          end)

          describe("GET", function()
            it("retrieves the seconds-level response code data for a given consumer", function()
              local consumer = assert(bp.consumers:insert_ws({
                username  = "bob",
                custom_id = "1234"
              }, db.workspaces:select_by_name("default")))

              local route = assert(bp.routes:insert_ws({
                paths = {"/my-route"}
              }, db.workspaces:select_by_name("default")))

              local route_id = route.id

              local now        = time()
              local minute     = now - (now % 60)
              local service_id = utils.uuid()

              local test_status_code_data = {
                { consumer.id, route_id, service_id, "404", tostring(now), "1", 4 },
                { consumer.id, route_id, service_id, "404", tostring(now - 1), "1", 2 },
                { consumer.id, route_id, service_id, "500", tostring(minute), "60", 5 },
              }

              assert(strategy:insert_status_codes_by_consumer_and_route(test_status_code_data))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval    = "seconds",
                  consumer_id = consumer.id,
                }
              })

              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  workspace_id = ngx.ctx.workspace,
                  entity_type = "consumer_route",
                  entity_id   = consumer.id,
                  earliest_ts = now - 1,
                  interval    = "seconds",
                  latest_ts   = now,
                  level       = "cluster",
                  stat_labels = {
                    "status_codes_per_consumer_route_total",
                  },
                  status_code_totals = {
                    ["404"] = 6,
                    ["total"] = 6,
                  },
                },
                stats = {
                  [route_id] = {
                    [tostring(now - 1)] = {
                      ["404"] = 2,

                    },
                    [tostring(now)] = {
                      ["404"] = 4,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("retrieves the minutes-level response code data for a given consumer", function()
              local consumer = assert(bp.consumers:insert_ws({
                username  = "bob",
                custom_id = "1234"
              }, db.workspaces:select_by_name("default")))

              local route = assert(bp.routes:insert_ws({
                paths = {"/my-route"}
              }, db.workspaces:select_by_name("default")))

              local route_id = route.id

              local minute_start_at = time() - (time() % 60)
              local service_id      = utils.uuid()

              local test_status_code_data = {
                { consumer.id, route_id, service_id, "404", tostring(minute_start_at), "60", 101},
                { consumer.id, route_id, service_id, "200", tostring(minute_start_at - 60), "60", 205},
                { consumer.id, route_id, service_id, "500", tostring(minute_start_at - 60), "60", 6},
              }

              assert(strategy:insert_status_codes_by_consumer_and_route(test_status_code_data))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval = "minutes",
                  consumer_id = consumer.id,
                }
              })
              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected = {
                meta = {
                  workspace_id = ngx.ctx.workspace,
                  entity_type = "consumer_route",
                  entity_id   = consumer.id,
                  earliest_ts = minute_start_at - 60,
                  interval    = "minutes",
                  latest_ts   = minute_start_at,
                  level       = "cluster",
                  stat_labels = {
                    "status_codes_per_consumer_route_total",
                  },
                  status_code_totals = {
                    ["200"] = 205,
                    ["404"] = 101,
                    ["500"] = 6,
                    ["total"] = 312,
                  },
                },
                stats = {
                  [route_id] = {
                    [tostring(minute_start_at - 60)] = {
                      ["200"] = 205,
                      ["500"] = 6,
                    },
                    [tostring(minute_start_at)] = {
                      ["404"] = 101,
                    },
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("returns a 400 if called with invalid interval", function()
              local consumer = assert(bp.consumers:insert_ws({
                username  = "bob",
                custom_id = "1234"
              }, db.workspaces:select_by_name("default")))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval = "seconds",
                  consumer_id = consumer.id,
                  start_ts = "foo",
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: start_ts must be a number", json.message)
            end)

            it("returns a 400 if called with invalid start_ts", function()
              local consumer = assert(db.consumers:insert {
                username  = "bob",
                custom_id = "1234"
              })

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval = "seconds",
                  consumer_id = consumer.id,
                  start_ts = "foo",
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: start_ts must be a number", json.message)
            end)

            it("returns a 404 if called with invalid consumer_id", function()
              local consumer_id = "shh.. I'm not a real consumer id"
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval = "minutes",
                  consumer_id = consumer_id,
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)

            it("returns a 404 if called with no consumer_id", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval = "minutes",
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)

            it("returns a 404 if called with a consumer_id that does not exist", function()
              local consumer_id = "20426633-55dc-4050-89ef-2382c95a611a"
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval = "minutes",
                  consumer_id = consumer_id,
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)
          end)
        end)

        describe("/vitals/consumers/{username_or_id}/cluster", function()
          before_each(function()
            db:truncate("consumers")
            db:truncate("vitals_consumers")
            db:truncate("vitals_codes_by_consumer_route")
          end)

          describe("GET", function()
            it("retrieves consumer stats (seconds)", function()
              local consumer = assert(db.consumers:insert {
                username = "bob",
                custom_id = "1234"
              })

              local now = time()

              assert(strategy:insert_status_codes_by_consumer_and_route({
                -- inserting minute and second data, but only expecting second data in response
                { consumer.id, utils.uuid(), utils.uuid(), "200", now, 60, 45 },
                { consumer.id, utils.uuid(), utils.uuid(), "200", now, 1, 17 }
              }))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/consumers/" .. consumer.id .. "/cluster",
                query = {
                  interval = "seconds"
                }
              })

              res = assert.res_status(200, res)
              local json = cjson.decode(res)

              local expected =  {
                meta = {
                  level = "cluster",
                  interval = "seconds",
                  earliest_ts = now,
                  latest_ts = now,
                  stat_labels = consumer_stat_labels,
                },
                stats = {
                  cluster = {
                    [tostring(now)] = 17
                  }
                }
              }

              assert.True(compare_no_order(expected, json))
            end)

            it("returns a 404 if called with invalid consumer_id path param", function()
              local res = assert(client:send {
                method = "GET",
                path = "/vitals/consumers/fake-uuid/cluster",
                query = {
                  interval = "seconds"
                }
              })
              res = assert.res_status(404, res)
              local json = cjson.decode(res)

              assert.same("Not found", json.message)
            end)

            it("returns a 400 if called with invalid interval", function()
              local consumer = assert(bp.consumers:insert_ws({
                username  = "bob",
                custom_id = "1234"
              }, db.workspaces:select_by_name("default")))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/consumers/" .. consumer.id .. "/cluster",
                query = {
                  wrong_query_key = "seconds"
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: consumer_id, duration, and level are required", json.message)
            end)

            it("returns a 400 if called with invalid start_ts", function()
              local consumer = assert(bp.consumers:insert_ws({
                username  = "bob",
                custom_id = "1234"
              }, db.workspaces:select_by_name("default")))

              local res = assert(client:send {
                method = "GET",
                path = "/vitals/consumers/" .. consumer.id .. "/cluster",
                query = {
                  interval = "seconds",
                  start_ts = "foo"
                }
              })
              res = assert.res_status(400, res)
              local json = cjson.decode(res)

              assert.same("Invalid query params: start_ts must be a number", json.message)
            end)
          end)
        end)
      end)

      describe("in release package", function()
        local reset_distribution

        setup(function()
          bp, db = helpers.get_db_utils(db_strategy, {"licenses"})
          reset_distribution = setup_distribution()

          assert(helpers.start_kong({
            database = db_strategy,
            portal = true,
            portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
            vitals = true,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            lua_package_path = "./?.lua;./?/init.lua;./spec/fixtures/?.lua",
          }))

          client = helpers.admin_client()
        end)

        teardown(function()
          if client then
            client:close()
          end

          helpers.stop_kong()
          reset_distribution()
        end)

        it("responds 404 without a license", function()
          local res = assert(client:send {
            method = "GET",
            path = "/vitals"
          })

          assert.res_status(404, res)
        end)

        it("responds 200 after loading license via Admin API", function()
          local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
          local d = f:read("*a")
          f:close()

          local res = assert(client:send {
            method = "POST",
            path = "/licenses",
            headers = {
              ["Content-Type"] = "application/json",
            },
            body = { payload = d },
          })
          assert.res_status(201, res)

          helpers.wait_until(function()
            local res = assert(client:send {
              method = "GET",
              path = "/vitals"
            })

            res:read_body()
            return res.status == 200
          end, 10)
        end)
      end)
    end)

    describe("when vitals is not enabled", function()
      setup(function()
        bp, db = helpers.get_db_utils(db_strategy)

        assert(helpers.start_kong({
          database = db_strategy,
          vitals   = false,
        }))

        client = helpers.admin_client()
      end)

      teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()
      end)

      describe("GET", function()

        it("responds 404", function()
          local res = assert(client:send {
            method = "GET",
            path = "/vitals"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)

end
