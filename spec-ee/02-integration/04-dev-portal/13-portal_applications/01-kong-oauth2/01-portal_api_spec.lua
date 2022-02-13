-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson      = require "cjson"
local pl_stringx = require "pl.stringx"
local helpers    = require "spec.helpers"
local utils      = require "kong.tools.utils"
local ee_helpers = require "spec-ee.helpers"


local PORTAL_SESSION_CONF = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }"
local DEFAULT_CONSUMER = {
  ["basic-auth"] = {
    headers = {
      ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
    },
    body = {
      email = "gruce@konghq.com",
      password = "kong",
      meta = "{\"full_name\":\"I Like Turtles\"}",
    },
  },
  ["key-auth"] = {
    headers = {
      ["apikey"] = "kongboi",
    },
    body = {
      email = "gruce@konghq.com",
      key = "kongboi",
      meta = "{\"full_name\":\"I Like Turtles\"}",
    },
  },
}

local function insert_files(db)
  for i = 1, 10 do
    local file_name = "file-" .. i
    assert(db.legacy_files:insert({
      name = file_name,
      contents = "i-" .. i,
      type = "partial",
      auth = i % 2 == 0 and true or false,
    }))

    local file_page_name = "file-page" .. i
    assert(db.legacy_files:insert({
      name = file_page_name,
      contents = "i-" .. i,
      type = "page",
      auth = i % 2 == 0 and true or false,
    }))
  end
end


local function verify_order(data, key, sort_desc)
  for i = 1, #data - 1 do
    local current_val = data[i][key]
    local next_val = data[i + 1][key]

    local current_is_nil = current_val == nil
    local next_is_nil = next_val == nil

    if current_is_nil then
      assert.is_true(not sort_desc or next_is_nil)
    elseif next_is_nil then
      assert.is_true(sort_desc)
    else
      assert.is_true(current_val == next_val or current_val > next_val == sort_desc)
    end
  end
end


local function register_developer(portal_api_client, body)
  if type(body) == "string" then
    body = DEFAULT_CONSUMER[body].body
  end

  return assert(portal_api_client:send {
    method = "POST",
    path = "/register",
    body = body,
    headers = {["Content-Type"] = "application/json"},
  })
end


local function authenticate(portal_api_client, headers, return_cookie)
  if type(headers) == "string" then
    headers = DEFAULT_CONSUMER[headers].headers
  end

  local res = assert(portal_api_client:send {
    method = "GET",
    path = "/auth",
    headers = headers
  })

  if return_cookie then
    assert.res_status(200, res)
    return assert.response(res).has.header("Set-Cookie")
  end

  return res
end


local function configure_portal(db, config)
  db.workspaces:upsert_by_name("default", {
    name = "default",
    config = config,
  })
end


local function close_clients(portal_api_client)
  if portal_api_client then
    portal_api_client:close()
  end
end

local function timestamp_to_date(ts)
    return os.date("!%Y-%m-%d", ts)
end

local rbac_mode = {"off", "on"}

for _, strategy in helpers.each_strategy() do
  for idx, rbac in ipairs(rbac_mode) do
    describe("Developer Portal - Portal API #" .. strategy .. " (ENFORCE_RBAC = " .. rbac .. ")", function()
      local portal_api_client
      local admin_client
      local _, db, _ = helpers.get_db_utils(strategy)

      lazy_teardown(function()
        helpers.stop_kong()
        assert(db:truncate())
      end)

      describe("/applications", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
            enforce_rbac = rbac,
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
            portal_auth_login_attempts = 3,
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("GET", function()
          local devs = { "dale", "bob", "ted" }

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res
            for _, dev in ipairs(devs) do
              res = register_developer(portal_api_client, {
                email = dev .. "@konghq.com",
                password = "kong",
                meta = "{\"full_name\":\"n00b\"}",
              })

              assert.res_status(200, res)

              local cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64(dev .. "@konghq.com:kong"),
              }, true)

              if dev ~= "ted" then
                for i = 1, 10, 1 do
                  res = assert(portal_api_client:send {
                    method = "POST",
                    path = "/applications",
                    body = {
                      name = dev .. "s_app_" .. i,
                      redirect_uri = "http://dog.com",
                      description = i % 2 == 0 and "something" or nil,
                    },
                    headers = {
                      ["Content-Type"] = "application/json",
                      ["Cookie"] = cookie
                    }
                  })

                  assert.res_status(200, res)
                end
              else
                local make_name = function(i)
                  if i == 3 or i == 8 then return dev .. "s_special_app_" .. i end
                  return dev .. "s_app_" .. i
                end
                
                local make_description = function(i)
                  if i % 2 == 1 then return 'odd' end
                  return 'even'
                end

                local make_created_at = function(i)
                  return os.time({
                    year = 2022, month = i, day = i
                  })
                end

                for i = 1, 10, 1 do
                  res = assert(portal_api_client:send {
                    method = "POST",
                    path = "/applications",
                    body = {
                      name = make_name(i),
                      redirect_uri = "http://dog.com",
                      description = make_description(i)
                    },
                    headers = {
                      ["Content-Type"] = "application/json",
                      ["Cookie"] = cookie
                    }
                  })

                  local body = assert.res_status(200, res)
                  local application = cjson.decode(body)

                  local created_at = make_created_at(i)

                  local updated = assert(db.applications:update({
                    id = application.id
                  }, {
                      created_at = created_at,
                  }))

                  assert.equal(created_at, updated.created_at)
                end
              end
            end
          end)


          lazy_teardown(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('developers'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
          end)

          it("Retrieves Applications only belonging to each developer", function()
            for _, dev in ipairs(devs) do
              local cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64(dev .. "@konghq.com:kong"),
              }, true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/applications",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)

              for i, row in ipairs(resp_body_json.data) do
                assert.equal(1, pl_stringx.lfind(row.name, dev))
              end

              assert.equal(10, resp_body_json.total)
            end
          end)

          it("return 400 if size is less than 1", function ()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?size=0",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("invalid size", resp_body_json.message)
          end)

          it("return 400 if size is greater than 1000", function ()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?size=1001",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("invalid size", resp_body_json.message)
          end)

          it("paginates properly", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?size=3",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(3, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(3, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(3, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)
            assert.equal(ngx.null, resp_body_json.next)
          end)

          it("sorts by id ASC by default", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "id", false)
          end)

          it("sorts by id DESC with 'sort_desc=true' param", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "id", true)
          end)

          it("sorts by name ASC with 'sort_by=name' param", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "name", false)
          end)

          it("sorts by name DESC with 'sort_by=name&sort_desc=true' param", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?sort_by=name&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "name", true)
          end)

          it("sorts by id ASC if sort_by values are the same", function ()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?sort_by=redirect_uri",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "id", false)
          end)

          it("sorts by id DESC if sort_by values are the same", function ()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?sort_by=redirect_uri&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "id", true)
          end)

          it("handles nil values when sorting ASC", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?sort_by=description",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "description", false)
          end)

          it("handles nil values when sorting DESC", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?sort_by=description&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "description", true)
          end)

          it("maintains sort across pages ASC", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?sort_by=name&size=5",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(5, resp_body_json.total)

            verify_order(resp_body_json.data, "name", false)

            local last_name_first_page = resp_body_json.data[#resp_body_json.data]

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(5, resp_body_json.total)

            verify_order(resp_body_json.data, "name", false)

            local first_name_second_page = resp_body_json.data[1]

            verify_order({last_name_first_page, first_name_second_page}, "name", false)
          end)

          it("maintains sort across pages DESC", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?sort_by=name&size=5&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(5, resp_body_json.total)

            verify_order(resp_body_json.data, "name", true)

            local last_name_first_page = resp_body_json.data[#resp_body_json.data]

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(5, resp_body_json.total)

            verify_order(resp_body_json.data, "name", true)

            local first_name_second_page = resp_body_json.data[1]

            verify_order({last_name_first_page, first_name_second_page}, "name", true)
          end)

          it("filters by id from query params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("ted@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            local id_param = resp_body_json.data[3].id

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?id=" .. id_param,
              headers = {
                ["Cookie"] = cookie
              }
            })

            body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)
            assert.equal(id_param, resp_body_json.data[1].id)
          end)

          it("filters by name from query params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("ted@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?name=app_&sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "name", false)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?name=special_app&sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)

            assert.equal(2, resp_body_json.total)
            assert.equal("teds_special_app_3", resp_body_json.data[1].name)
            assert.equal("teds_special_app_8", resp_body_json.data[2].name)
          end)

          it("filters by description from query params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("ted@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?description=odd&sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(5, resp_body_json.total)
            assert.equal("odd", resp_body_json.data[1].description)
            assert.equal("odd", resp_body_json.data[2].description)
            assert.equal("odd", resp_body_json.data[3].description)
            assert.equal("odd", resp_body_json.data[4].description)
            assert.equal("odd", resp_body_json.data[5].description)

            verify_order(resp_body_json.data, "name", false)
          end)

          it("filters by created_at_from from query params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("ted@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?created_at_from=2022-03-03&sort_by=created_at",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(8, resp_body_json.total)
            assert.equal("2022-03-03", timestamp_to_date(resp_body_json.data[1].created_at))
            assert.equal("2022-04-04", timestamp_to_date(resp_body_json.data[2].created_at))
            assert.equal("2022-05-05", timestamp_to_date(resp_body_json.data[3].created_at))
            assert.equal("2022-06-06", timestamp_to_date(resp_body_json.data[4].created_at))
            assert.equal("2022-07-07", timestamp_to_date(resp_body_json.data[5].created_at))
            assert.equal("2022-08-08", timestamp_to_date(resp_body_json.data[6].created_at))
            assert.equal("2022-09-09", timestamp_to_date(resp_body_json.data[7].created_at))
            assert.equal("2022-10-10", timestamp_to_date(resp_body_json.data[8].created_at))
          end)

          it("filters by created_at_to from query params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("ted@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?created_at_to=2022-06-06&sort_by=created_at",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(6, resp_body_json.total)
            assert.equal("2022-01-01", timestamp_to_date(resp_body_json.data[1].created_at))
            assert.equal("2022-02-02", timestamp_to_date(resp_body_json.data[2].created_at))
            assert.equal("2022-03-03", timestamp_to_date(resp_body_json.data[3].created_at))
            assert.equal("2022-04-04", timestamp_to_date(resp_body_json.data[4].created_at))
            assert.equal("2022-05-05", timestamp_to_date(resp_body_json.data[5].created_at))
            assert.equal("2022-06-06", timestamp_to_date(resp_body_json.data[6].created_at))
          end)

          it("filters between created_at_from and created_at_to from query params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("ted@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?created_at_from=2022-03-03&created_at_to=2022-06-06&sort_by=created_at",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(4, resp_body_json.total)
            assert.equal("2022-03-03", timestamp_to_date(resp_body_json.data[1].created_at))
            assert.equal("2022-04-04", timestamp_to_date(resp_body_json.data[2].created_at))
            assert.equal("2022-05-05", timestamp_to_date(resp_body_json.data[3].created_at))
            assert.equal("2022-06-06", timestamp_to_date(resp_body_json.data[4].created_at))
          end)

          it("filters all rows out when invalid created_at_from or created_at_to from query params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("ted@konghq.com:kong"),
            }, true)

            local invalid_dates = { "", "yo", "2022-01-" }

            for _, v in ipairs(invalid_dates) do
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/applications?created_at_from=" .. v .. "&sort_by=created_at",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)

              assert.equal(0, resp_body_json.total)
            end

            for _, v in ipairs(invalid_dates) do
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/applications?created_at_to=" .. v .. "&sort_by=created_at",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)

              assert.equal(0, resp_body_json.total)
            end
          end)
        end)

        describe("POST", function()
          local developer, developer_two

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            developer = resp_body_json.developer

            local res = register_developer(portal_api_client, {
              email = "dev2@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"wow\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            developer_two = resp_body_json.developer
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("should return 200 when creating a valid application", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("myfirstapp", resp_body_json.name)
            assert.equal("http://dog.com", resp_body_json.redirect_uri)
          end)

          it("ignores developer in body", function()
            assert.is_nil(db.consumers:select_by_username(developer.id .. "_new_app"))
            assert.is_nil(db.consumers:select_by_username(developer_two.id .. "_new_app"))

            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "new_app",
                redirect_uri = "http://dog.com",
                developer = { id = developer_two.id },
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(developer.id, resp_body_json.developer.id)
            assert(db.consumers:select_by_username(developer.id .. "_new_app"))
            assert.is_nil(db.consumers:select_by_username(developer_two.id .. "_new_app"))
          end)

          it("should return 409 when creating a pre-existing application", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(409, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("application already exists with name: 'myfirstapp'", resp_body_json.fields.name)
          end)

          it("should return 409 when creating a pre-existing application with whitespace added to name", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp ",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(409, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("application already exists with name: 'myfirstapp'", resp_body_json.fields.name)
          end)

          it("should return 400 if does not contain proper params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("required field missing", resp_body_json.fields.name)
          end)
        end)
      end)

      describe("/applications/:applications", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("GET", function()
          local application, cookie

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("developer gets 200 when requesting a valid application", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id,
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("myfirstapp", resp_body_json.name)
            assert.equal("http://dog.com", resp_body_json.redirect_uri)
          end)

          it("developer gets 400 when requesting a non-existent Application", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. utils.uuid(),
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(404, res)
          end)
        end)

        describe("PATCH", function()
          local application, application_2, cookie, dev2_cookie, dev2_application

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myotherapp",
                redirect_uri = "http://dog.com",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application_2 = cjson.decode(body)

            local res = register_developer(portal_api_client, {
              email = "chip@konghq.com",
              password = "kongboi",
              meta = "{\"full_name\":\"lol\"}",
            })

            assert.res_status(200, res)

            dev2_cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("chip@konghq.com:kongboi"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "dev2app",
                redirect_uri = "http://dev2.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = dev2_cookie
              }
            })

            local body = assert.res_status(200, res)
            dev2_application = cjson.decode(body)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("empty patch does nothing", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(application.name, resp_body_json.name)
            assert.equal(application.redirect_uri, resp_body_json.redirect_uri)
            assert.is_nil(application.description)
          end)

          it("developer can update application", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                name = "mysecondapp",
                redirect_uri = "http://cat.com",
                description = "something new!",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("mysecondapp", resp_body_json.name)
            assert.equal("http://cat.com", resp_body_json.redirect_uri)
            assert.equal("something new!", resp_body_json.description)
          end)

          it("developer cannot update application with duplicate name", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                name = application_2.name,
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(409, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("application already exists with name: 'myotherapp'", resp_body_json.fields.name)
          end)

          it("developer cannot update application with invalid 'redirect_uri'", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                redirect_uri = "bobobo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("missing host in url", resp_body_json.fields.redirect_uri)
          end)

          it("developer cannot update application with null 'redirect_uri'", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                redirect_uri = ngx.null,
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("required field missing", resp_body_json.fields.redirect_uri)
          end)

          it("developer cannot update applications foreign keys", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                consumer = { id = utils.uuid() },
                developer = { id = utils.uuid() },
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(application.consumer.id, resp_body_json.consumer.id)
            assert.equal(application.developer.id, resp_body_json.developer.id)
          end)

          it("developer cannot update id of application FTI-3016", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                id = dev2_application.id
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(application.id, resp_body_json.id)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id,
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(application.id, resp_body_json.id)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications",
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })
            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(2, #resp_body_json.data)

            local app_ids = {}

            for _, app in ipairs(resp_body_json.data) do
              app_ids[app.id] = true
            end

            assert.True(app_ids[application.id])
            assert.True(app_ids[application_2.id])
            assert.is_nil(app_ids[dev2_application.id])

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications",
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = dev2_cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(1, #resp_body_json.data)
            assert.equal(dev2_application.id, resp_body_json.data[1].id)
          end)
        end)

        describe("DELETE", function()
          local application, cookie

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("developer can delete application", function()
            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/applications/" .. application.id,
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(204, res)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id,
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(404, res)
          end)
        end)
      end)

      describe("/applications/:applications/credentials", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("GET", function()
          local application, cookie

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            for i=1, 9 do
              res = assert(portal_api_client:send {
                method = "POST",
                path = "/applications/" .. application.id .. "/credentials",
                body = {},
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie
                }
              })

              assert.res_status(201, res)
            end
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("developer can retrieve credentials attached to application", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            for i, credential in ipairs(resp_body_json.data) do
              assert.equal(application.consumer.id, credential.consumer.id)
            end

            assert.equal(10, resp_body_json.total)
          end)

          it("return 400 if size is less than 1", function ()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?size=0",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("invalid size", resp_body_json.message)
          end)

          it("return 400 if size is greater than 1000", function ()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?size=1001",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("invalid size", resp_body_json.message)
          end)

          it("paginates properly", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?size=4",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)

            assert.equal(2, resp_body_json.total)
            assert.equal(ngx.null, resp_body_json.next)
          end)

          it("sorts by id ASC by default", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "id", false)
          end)

          it("sorts by id DESC with 'sort_desc=true' param", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "id", true)
          end)

          it("sorts by client_id ASC with 'sort_by=client_id' param", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?sort_by=client_id",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "client_id", false)
          end)

          it("sorts by client_id DESC with 'sort_by=client_id&sort_desc=true' param", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?sort_by=client_id&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "client_id", true)
          end)

          it("sorts by id ASC if sort_by values are the same", function ()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "id", false)
          end)

          it("sorts by id DESC if sort_by values are the same", function ()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?sort_by=name&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(10, resp_body_json.total)

            verify_order(resp_body_json.data, "id", true)
          end)

          it("maintains sort across pages ASC", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?sort_by=client_id&size=5",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(5, resp_body_json.total)

            verify_order(resp_body_json.data, "client_id", false)

            local last_name_first_page = resp_body_json.data[#resp_body_json.data]

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(5, resp_body_json.total)

            verify_order(resp_body_json.data, "client_id", false)

            local first_name_second_page = resp_body_json.data[1]

            verify_order({last_name_first_page, first_name_second_page}, "client_id", false)
          end)

          it("maintains sort across pages DESC", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?sort_by=client_id&size=5&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(5, resp_body_json.total)

            verify_order(resp_body_json.data, "client_id", true)

            local last_name_first_page = resp_body_json.data[#resp_body_json.data]

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(5, resp_body_json.total)

            verify_order(resp_body_json.data, "client_id", true)

            local first_name_second_page = resp_body_json.data[1]

            verify_order({last_name_first_page, first_name_second_page}, "client_id", true)
          end)

          it("filters by client_id from query params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?sort_by=client_id&size=5&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(5, resp_body_json.total)

            local client_id_param = resp_body_json.data[4].client_id


            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?size=5&client_id=" .. client_id_param,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)
            assert.equal(client_id_param, resp_body_json.data[1].client_id)
          end)
        end)

        describe("POST", function()
          local application, cookie

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)
          end)


          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("developer can create an application credential", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(application.consumer.id, resp_body_json.consumer.id)

            local key_auth_cred_created = false

            for row, err in db.daos["keyauth_credentials"]:each_for_consumer({ id = application.consumer.id }) do
              if row.key == resp_body_json.client_id then
                key_auth_cred_created = true
              end
            end

            assert.is_true(key_auth_cred_created)
          end)
        end)
      end)

      describe("/applications/:applications/credentials/:credentials", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("GET", function()
          local application, cookie, credential

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            credential = cjson.decode(body).data[1]
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("can GET a specific credential", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials/" .. credential.id,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(credential.id, resp_body_json.id)
          end)
        end)

        describe("DELETE", function()
          local application, cookie, credential

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            credential = cjson.decode(body).data[1]
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("can DELETE a specific credential", function()
            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/applications/" .. application.id .. "/credentials/" .. credential.id,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(204, res)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(0, #resp_body_json.data)

            local key_auth_cred_deleted = true

            for row, err in db.daos["keyauth_credentials"]:each_for_consumer({ id = application.consumer.id }) do
              if row.key == credential.client_id then
                key_auth_cred_deleted = false
              end
            end

            assert.is_true(key_auth_cred_deleted)
          end)
        end)
      end)

      describe("/applications/:applications/application_instances", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client, admin_client)
        end)

        describe("POST", function()
          local application, cookie, service_id

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            admin_client = assert(helpers.admin_client())


            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            local res = assert(admin_client:send {
              method = "POST",
              path = "/services",
              body = {
                name = "myfirstservice",
                host = "example.com",
                protocol = "http"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            local body = assert.res_status(201, res)
            service_id = assert(cjson.decode(body).id)

            assert(db.plugins:insert({
              config = {
                enable_authorization_code = true,
              },
              name = "oauth2",
              service = { id = service_id },
            }))

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
            assert(db:truncate('services'))

          end)

          it("can POST a new application instance", function()

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(service_id, resp_body_json.service.id)
            assert.equal(1, resp_body_json.status)
          end)

          it("returns 400 with missing service id", function()

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {}
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(400, res)
          end)
        end)

        describe("GET", function()
          local application, cookie, service_id, service_id2

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            admin_client = assert(helpers.admin_client())


            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            local res = assert(admin_client:send {
              method = "POST",
              path = "/services",
              body = {
                name = "myfirstservice",
                host = "example.com",
                protocol = "http"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            body = assert.res_status(201, res)
            service_id = assert(cjson.decode(body).id)

            assert(db.plugins:insert({
              config = {
                enable_authorization_code = true,
              },
              name = "oauth2",
              service = { id = service_id },
            }))

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))

            res = assert(admin_client:send {
              method = "POST",
              path = "/services",
              body = {
                name = "mysecondservice",
                host = "example.com",
                protocol = "http"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            local body = assert.res_status(201, res)
            service_id2 = assert(cjson.decode(body).id)

            assert(db.plugins:insert({
              config = {
                enable_authorization_code = true,
              },
              name = "oauth2",
              service = { id = service_id2 },
            }))

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id2 },
            }))

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

            -- TODO: replace with db.insert?
            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id,
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(201, res)

            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id2,

                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })
            assert.res_status(201, res)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
            assert(db:truncate('services'))
          end)

          it("can GET list of application instances", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(2, resp_body_json.total)
          end)

          it("paginates properly", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/application_instances?size=1",
              body = {
                service = {
                  id = service_id
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              body = {
                service = {
                  id = service_id
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)

            assert.equal(ngx.null, resp_body_json.next)
          end)
        end)
      end)

      describe("/applications/:applications/application_instances/:application_instances", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client, admin_client)
        end)

        describe("GET", function()
          local application, cookie, service_id, application_instance_id

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            admin_client = assert(helpers.admin_client())


            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            local res = assert(admin_client:send {
              method = "POST",
              path = "/services",
              body = {
                name = "myfirstservice",
                host = "example.com",
                protocol = "http"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            body = assert.res_status(201, res)
            service_id = assert(cjson.decode(body).id)

            assert(db.plugins:insert({
              config = {
                enable_authorization_code = true,
              },
              name = "oauth2",
              service = { id = service_id },
            }))

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id,
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            body = assert.res_status(201, res)
            application_instance_id = assert(cjson.decode(body).id)

          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
            assert(db:truncate('services'))

          end)

          it("can GET a application instance", function()

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/application_instances/" .. application_instance_id,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert(resp_body_json.service.id, service_id)
          end)
        end)

        describe("DELETE", function()
          local application, cookie, service_id, application_instance_id

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            admin_client = assert(helpers.admin_client())


            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            local res = assert(admin_client:send {
              method = "POST",
              path = "/services",
              body = {
                name = "myfirstservice",
                host = "example.com",
                protocol = "http"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            body = assert.res_status(201, res)
            service_id = assert(cjson.decode(body).id)

            assert(db.plugins:insert({
              config = {
                enable_authorization_code = true,
              },
              name = "oauth2",
              service = { id = service_id },
            }))

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id,
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            body = assert.res_status(201, res)
            application_instance_id = assert(cjson.decode(body).id)

          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
            assert(db:truncate('services'))
          end)

          it("can DELETE a application instance", function()
            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/applications/" .. application.id .. "/application_instances/" .. application_instance_id,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })
            assert.res_status(204, res)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/application_instances/" .. application_instance_id,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(404, res)
          end)
        end)
      end)

      describe("/application_services", function()
        local application
        local application_jim

        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client, admin_client)
        end)

        describe("GET", function()
          local cookie, service_id, developer

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            admin_client = assert(helpers.admin_client())

            local res = register_developer(portal_api_client, {
              email = "jim@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            local cookie_jim = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("jim@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "jim's app",
                redirect_uri = "http://cat.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie_jim
              }
            })

            local body = assert.res_status(200, res)
            application_jim =  assert(cjson.decode(body))

            local res = assert(admin_client:send {
              method = "POST",
              path = "/developers/roles",
              body = {
                name = "role1"
              },
              headers = {["Content-Type"] = "application/json"},
            })

            assert.res_status(201, res)

            local res = assert(admin_client:send {
              method = "POST",
              path = "/developers/roles",
              body = {
                name = "role2"
              },
              headers = {["Content-Type"] = "application/json"},
            })

            assert.res_status(201, res)

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            developer = resp_body_json.developer

            local res = assert(admin_client:send {
              method = "PATCH",
              path = "/developers/" .. developer.id,
              body = {
                roles = { "role1" },
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application =  assert(cjson.decode(body))

            for i=1, 10 do
              local res = assert(admin_client:send {
                method = "POST",
                path = "/services",
                body = {
                  name = "myservice-" .. i,
                  host = "example.com",
                  protocol = "https"
                },
                headers = {
                  ["Content-Type"] = "application/json"
                }
              })

              local body = assert.res_status(201, res)

              if i % 2 == 0 then
                service_id = assert(cjson.decode(body).id)

                assert(db.plugins:insert({
                  config = {
                    enable_authorization_code = i % 4 == 0,
                    enable_implicit_grant = i % 4 ~= 0,
                  },
                  name = "oauth2",
                  service = { id = service_id },
                }))

                local display_name = "" .. i
                if i == 6 or i == 8 then
                  display_name = "" .. i .. " : regular"
                elseif i == 2 or i == 10 then
                  display_name = "" .. i .. " : irregular"
                end

                assert(db.plugins:insert({
                  config = {
                    display_name = display_name,
                  },
                  name = "application-registration",
                  service = { id = service_id },
                }))

                local function make_status(i)
                  if i == 2 then return 0
                  elseif i == 8 then return 1
                  elseif i == 10 then return 3
                  end
                  return -1
                end

                local instance_status = make_status(i)

                if instance_status ~= -1 then
                  res = assert(portal_api_client:send {
                    method = "POST",
                    path = "/applications/" .. application.id .. "/application_instances",
                    body = {
                      service = {
                        id = service_id,
                      }
                    },
                    headers = {
                      ["Cookie"] = cookie,
                      ["Content-Type"] = "application/json",
                    }
                  })

                  body = assert.res_status(201, res)
                  local application_instance =  assert(cjson.decode(body))

                  res = assert(admin_client:send {
                    method = "PATCH",
                    path = "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
                    body = {
                      status = instance_status
                    },
                    headers = {["Content-Type"] = "application/json"},
                  })

                  assert.res_status(200, res)
                end
  
                local doc_config

                if i == 2 then
                  doc_config = {
                    contents = [[{
                      "x-headmatter": {"readable_by": ["role1"]}
                    }]],
                    path = "specs/role1.json",
                  }
                end

                if i == 4 then
                  doc_config = {
                    contents = [[{
                      "x-headmatter": {"readable_by": ["role2"]}
                    }]],
                    path = "specs/role2.json",
                  }
                end

                if i == 6 then
                  doc_config = {
                    contents = [[{
                      "x-headmatter": {"readable_by": "*"}
                    }]],
                    path = "specs/star.json",
                  }
                end

                if i == 8 then
                  doc_config = {
                    contents = [[{
                      "x-headmatter": {}
                    }]],
                    path = "specs/noroles.json",
                  }
                end

                if doc_config then
                  local res = assert(admin_client:send {
                    method = "POST",
                    path = "/files",
                    body = doc_config,
                    headers = {["Content-Type"] = "application/json"}
                  })

                  assert.res_status(201, res)

                  local res = assert(admin_client:send {
                    method = "POST",
                    path = "/services/" .. service_id .. "/document_objects",
                    body = {
                      path = doc_config.path
                    },
                    headers = {["Content-Type"] = "application/json"}
                  })

                  assert.res_status(200, res)
                end
              end
            end
          end)

          lazy_teardown(function()
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
            assert(db:truncate('services'))
          end)

          local function index_from_name(name)
            return tonumber(string.sub(name, 1, (string.find(name, ":") or #name + 1) - 1))
          end

          it("can GET a list of services with Application Registration applied", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)

            for i, v in ipairs(resp_body_json.data) do
              assert.equal(v.app_registration_config.display_name, v.name)
              assert.equal(v.auth_plugin_config.enable_authorization_code, index_from_name(v.name) % 4 == 0)
              assert.equal(v.auth_plugin_config.enable_implicit_grant, index_from_name(v.name) % 4 ~= 0)
            end
          end)

          it("can GET a list of services with Application Registration applied when non service oauth2 plugin (regression)", function()
            assert(db.plugins:insert({
              config = {
                enable_authorization_code = true,
                enable_implicit_grant = true,
              },
              name = "oauth2",
            }))

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)

            for i, v in ipairs(resp_body_json.data) do
              assert.equal(v.app_registration_config.display_name, v.name)
              assert.equal(v.auth_plugin_config.enable_authorization_code, index_from_name(v.name) % 4 == 0)
              assert.equal(v.auth_plugin_config.enable_implicit_grant, index_from_name(v.name) % 4 ~= 0)
            end
          end)

          it("paginates properly", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?size=2",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(2, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(2, resp_body_json.total)

            assert.equal(ngx.null, resp_body_json.next)
          end)

          it("sorts by id ASC by default", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(4, resp_body_json.total)

            verify_order(resp_body_json.data, "id", false)
          end)

          it("sorts by id DESC with 'sort_desc=true' param", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(4, resp_body_json.total)

            verify_order(resp_body_json.data, "id", true)
          end)

          it("sorts by name ASC with 'sort_by=name' param", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(4, resp_body_json.total)

            verify_order(resp_body_json.data, "name", false)
          end)

          it("sorts by name DESC with 'sort_by=name&sort_desc=true' param", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?sort_by=name&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(4, resp_body_json.total)

            verify_order(resp_body_json.data, "name", true)
          end)

          it("sorts by id ASC if sort_by values are the same", function ()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?sort_by=host",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(4, resp_body_json.total)

            verify_order(resp_body_json.data, "id", false)
          end)

          it("sorts by id DESC if sort_by values are the same", function ()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?sort_by=host&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(4, resp_body_json.total)

            verify_order(resp_body_json.data, "id", true)
          end)

          it("maintains sort across pages ASC", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?sort_by=name&size=2",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(2, resp_body_json.total)

            verify_order(resp_body_json.data, "name", false)

            local last_name_first_page = resp_body_json.data[#resp_body_json.data]

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(2, resp_body_json.total)

            verify_order(resp_body_json.data, "name", false)

            local first_name_second_page = resp_body_json.data[1]

            verify_order({last_name_first_page, first_name_second_page}, "name", false)
          end)

          it("maintains sort across pages DESC", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?sort_by=name&size=2&sort_desc=true",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(2, resp_body_json.total)

            verify_order(resp_body_json.data, "name", true)

            local last_name_first_page = resp_body_json.data[#resp_body_json.data]

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(2, resp_body_json.total)

            verify_order(resp_body_json.data, "name", true)

            local first_name_second_page = resp_body_json.data[1]

            verify_order({last_name_first_page, first_name_second_page}, "name", true)
          end)

          it("filters by name from query params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?name=regular&sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(4, resp_body_json.total)
            assert.equal("10 : irregular", resp_body_json.data[1].name)
            assert.equal("2 : irregular", resp_body_json.data[2].name)
            assert.equal("6 : regular", resp_body_json.data[3].name)
            assert.equal("8 : regular", resp_body_json.data[4].name)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?name=irreg&sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)

            assert.equal(2, resp_body_json.total)
            assert.equal("10 : irregular", resp_body_json.data[1].name)
            assert.equal("2 : irregular", resp_body_json.data[2].name)
          end)

          it("returns 404 if given query param app_id for an app that doesn't belong to developer", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?app_id=" .. application_jim.id .. "&sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(404, res)
            local resp_body_json = cjson.decode(body)
            assert.equal("Application not found", resp_body_json.message)
          end)

          it("returns 404 if given query param app_id for an app that doesn't exist", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?app_id=c7558663-4929-45a1-acd8-fbf6b0c586be&sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(404, res)
            local resp_body_json = cjson.decode(body)
            assert.equal("Application not found", resp_body_json.message)
          end)

          it("returns application_instances if given query param app_id", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?app_id=" .. application.id .. "&sort_by=name",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(4, resp_body_json.total)

            assert.equal("10 : irregular", resp_body_json.data[1].name)
            assert(resp_body_json.data[1].instance)
            assert.equal("2 : irregular", resp_body_json.data[2].name)
            assert(resp_body_json.data[2].instance)
            assert.equal("6 : regular", resp_body_json.data[3].name)
            assert.equal(nil, resp_body_json.data[3].instance)
            assert.equal("8 : regular", resp_body_json.data[4].name)
            assert(resp_body_json.data[4].instance)
          end)

          it("filters by query params status when app_id is present in query params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?app_id=" .. application.id .. "&sort_by=name&status=-1",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)

            assert.equal("6 : regular", resp_body_json.data[1].name)
            assert.equal(nil, resp_body_json.data[1].instance)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?app_id=" .. application.id .. "&sort_by=name&status=0",
              headers = {
                ["Cookie"] = cookie
              }
            })

            body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)

            assert.equal("2 : irregular", resp_body_json.data[1].name)
            assert(resp_body_json.data[1].instance)
            assert.equal(0, resp_body_json.data[1].instance.status)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?app_id=" .. application.id .. "&sort_by=name&status=1",
              headers = {
                ["Cookie"] = cookie
              }
            })

            body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)

            assert.equal("8 : regular", resp_body_json.data[1].name)
            assert(resp_body_json.data[1].instance)
            assert.equal(1, resp_body_json.data[1].instance.status)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?app_id=" .. application.id .. "&sort_by=name&status=2",
              headers = {
                ["Cookie"] = cookie
              }
            })

            body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)

            assert.equal(0, resp_body_json.total)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?app_id=" .. application.id .. "&sort_by=name&status=3",
              headers = {
                ["Cookie"] = cookie
              }
            })

            body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)

            assert.equal("10 : irregular", resp_body_json.data[1].name)
            assert(resp_body_json.data[1].instance)
            assert.equal(3, resp_body_json.data[1].instance.status)

          end)

          it("returns a permissioned service when the developer is assigned the proper role", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)

            local res = assert(admin_client:send {
              method = "PATCH",
              path = "/developers/" .. developer.id,
              body = {
                roles = { "role1", "role2" },
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            assert.res_status(200, res)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(5, resp_body_json.total)
          end)

          it("doesn't return a permissioned service when the role is removed from the developer", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(5, resp_body_json.total)

            local res = assert(admin_client:send {
              method = "PATCH",
              path = "/developers/" .. developer.id,
              body = {
                roles = { "role2" },
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            assert.res_status(200, res)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)
          end)
        end)
      end)
    end)
  end
end
