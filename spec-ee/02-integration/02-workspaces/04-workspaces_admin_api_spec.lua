-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers     = require "spec.helpers"
local cjson       = require "cjson"
local utils       = require "kong.tools.utils"
local workspaces  = require "kong.workspaces"
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

local PORTAL_SESSION_CONF = {
  storage = "kong",
  cookie_name = "portal_cookie",
  secret = "shh"
}
for _, strategy in helpers.each_strategy() do

describe("Workspaces Admin API (#" .. strategy .. "): ", function()
  local client,  db, bp
  local reset_license_data

  lazy_setup(function()
    reset_license_data = clear_license_env()
    bp, db = helpers.get_db_utils(strategy)

    db:truncate("workspaces")
    assert(helpers.start_kong({
      database = strategy,
      portal = true,
      portal_and_vitals_key = get_portal_and_vitals_key(),
      license_path = "spec-ee/fixtures/mock_license.json",
    }))
  end)

  before_each(function()
    if client then
      client:close()
    end
    client = assert(helpers.admin_client())
  end)

  lazy_teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
    reset_license_data()
  end)

  describe("/workspaces", function()
    describe("POST", function()
      it("creates a new workspace", function()
        local res = assert(client:post("/workspaces", {
          body   = {
            name = "foo",
            meta = {
              color = "#92b6d5"
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.id))
        assert.equals("foo", json.name)

        -- no files created, portal is off
        local files_count = 0
        for f, err in db.files:each() do
          files_count = files_count + 1
        end
        assert.equals(0, files_count)
      end)

      it("handles workspace name with special characters on creation", function()
        local res = assert(client:post("/workspaces", {
          body = {
            name = "ws-Áæ",
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.id))
        assert.equals("ws-Áæ", json.name)
      end)

      it("handles empty workspace name passed on creation", function()
        local res = assert(client:post("/workspaces", {
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("required field missing", json.fields.name)
      end)

      it("handles unique constraint conflicts", function()
        bp.workspaces:insert({
          name = "uniquefoo",
        })
        local res = assert(client:post("/workspaces", {
          body   = {
            name = "uniquefoo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(409, res)
      end)

      it("handles invalid meta json", function()
        local res = assert(client:post("/workspaces", {
          body   = {
            name = "foo",
            meta = "{ color: red }" -- invalid json
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("expected a record", json.fields.meta)
      end)

      it("creates default files if portal is ON", function()
        local res = assert(client:post("/workspaces", {
          body   = {
            name = "ws-with-portal",
            config = {
              portal = true
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.id))
        assert.equals("ws-with-portal", json.name)

        helpers.wait_until(function()
          local client = assert(helpers.admin_client())
          local res = assert(client:get("/ws-with-portal/files"))
          if res.status ~= 200 then
            client:close()
            return false
          end
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          client:close()
          return #json.data > 0
        end)
      end)

      describe("portal_auth_conf", function()

        it("(basic-auth) handles invalid config object", function()
          local res = assert(client:post("/workspaces", {
            body   = {
              name = "foo",
              config = {
                portal_auth = "basic-auth",
                portal_auth_conf = {
                  ["abc"] = "123"
                }
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equals("unknown field", json.message.config.abc)
        end)

        it("(basic-auth) handles invalid config type", function()
          local res = assert(client:post("/workspaces", {
            body   = {
              name = "foo",
              config = {
                portal_auth = "basic-auth",
                portal_auth_conf = "hello"
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equals("'config.portal_auth_conf' must be type 'table'", json.message)
        end)

        it("(basic-auth) accepts valid config", function()
          local res = assert(client:post("/workspaces", {
            body   = {
              name = "basicvalid",
              config = {
                portal_auth = "basic-auth",
                portal_auth_conf = {
                  hide_credentials = true
                },
                portal_session_conf = PORTAL_SESSION_CONF,
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equals(json.config.portal_auth_conf, '{"hide_credentials":true}')
        end)

        it("(key-auth) handles invalid config object", function()
          local res = assert(client:post("/workspaces", {
            body   = {
              name = "foo",
              config = {
                portal_auth = "key-auth",
                portal_auth_conf = {
                  ["abc"] = "123"
                }
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equals("unknown field", json.message.config.abc)
        end)

        it("(key-auth) handles invalid config type", function()
          local res = assert(client:post("/workspaces", {
            body   = {
              name = "foo",
              config = {
                portal_auth = "key-auth",
                portal_auth_conf = "hello"
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equals("'config.portal_auth_conf' must be type 'table'", json.message)
        end)

        it("(key-auth) accepts valid config", function()
          local res = assert(client:post("/workspaces", {
            body   = {
              name = "keyvalid",
              config = {
                portal_auth = "key-auth",
                portal_auth_conf = {
                  hide_credentials = true
                },
                portal_session_conf = PORTAL_SESSION_CONF
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equals(json.config.portal_auth_conf, '{"hide_credentials":true}')
        end)

        it("portal-meta-fields handles invalid config", function()
          local res = assert(client:post("/workspaces", {
            body   = {
              name = "foo",
              config = {
                portal_auth = "key-auth",
                portal_auth_conf = {
                  hide_credentials = true,
                },
                portal_developer_meta_fields = cjson.encode({{
                  label = "Gotcha",
                  title = "gotcha"
                }}),
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          assert.res_status(400, res)
        end)

        it("portal-meta-fields accepts valid config", function()
          local meta_fields = {{
            label = "TEST",
            title = "test",
            validator = {
              type = "string",
              required = true
            }
          }}

          local res = assert(client:post("/workspaces", {
            body   = {
              name = "portalmetavalid",
              config = {
                portal_auth = "key-auth",
                portal_auth_conf = {
                  hide_credentials = true
                },
                portal_developer_meta_fields = cjson.encode(meta_fields),
                portal_session_conf = PORTAL_SESSION_CONF
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          local meta_json = cjson.decode(json.config.portal_developer_meta_fields)
          assert.same(meta_json, meta_fields)

        end)
      end)
    end)

    describe("GET", function()
      lazy_setup(function()
        helpers.stop_kong()
        db:truncate("workspaces")
        db:truncate("services")
        db:truncate("consumers")
        assert(helpers.start_kong({
          database = strategy,
          portal = true,
          portal_and_vitals_key = get_portal_and_vitals_key(),
          license_path = "spec-ee/fixtures/mock_license.json",
        }))
      end)

      it("retrieves a list of workspaces", function()
        local num_to_create = 4
        assert(bp.workspaces:insert_n(num_to_create))

        local res = assert(client:send {
          method = "GET",
          path   = "/workspaces",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- total is number created + default
        assert.equals(num_to_create + 1, #json.data)
      end)

      it("retrieves workspace entity counter of workspaces", function()
        local num_to_create = 4
        assert(bp.workspaces:insert({ name = "ws1" }))
        local res = assert(client:post("/ws1/services", {
          body = {
            name = "service1",
            host = "a.upstream.test",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)
        for i = 1, num_to_create do
          res = assert(client:post("/ws1/consumers", {
            body = {
              username = "username" .. i,
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))
          assert.res_status(201, res)
        end

        local res = assert(client:send {
          method = "GET",
          path   = "/workspaces?counter=true",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        local data = json.data
        for _, value in pairs(data) do
          if value.name == 'ws1' then
            if value.counters then
              local counters = value.counters
              assert.equals(counters.services, 1)
              assert.equals(counters.consumers, num_to_create)
            end
          end
        end
      end)

      it("handles a list of workspaces with special chars", function()
        -- add a ws that contains special chars
        assert(bp.workspaces:insert({
          name = "ws-Áæ",
        }))

        local res = assert(client:send {
          method = "GET",
          path   = "/workspaces",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- make sure the name is properly returned by the endpoint
        local ws_found = false
        for _, ws in pairs(json.data) do
          if ws.name == "ws-Áæ" then
            ws_found = true
          end
        end
        assert.True(ws_found, "workspace ws-Áæ not found.")
      end)

      it("returns 404 if called from other than default workspace", function()
        assert.res_status(404, client:get("/bar/workspaces"))
        assert.res_status(200, client:get("/default/workspaces"))
      end)

      it("returns 400 if called reserved workspace names", function()
        assert.res_status(400, client:get("/workspaces/services"))
      end)
    end)
  end)

  describe("/workspaces/:workspace", function()
    describe("PUT", function()
      it("refuses to update the workspace name", function()
        -- PUT should work as workspace `foo_put` not present
        local res = assert(client:put("/default/workspaces/foo_put/", {
          body = {
            comment = "test PUT",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        assert.res_status(200, res)

        local res = assert(client:put("/workspaces/foo_put", {
          body = {
            name = "new_foo_put",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("Cannot rename a workspace", json.message)
      end)


    end)

    describe("PATCH", function()
      it("refuses to update the workspace name", function()
        assert(bp.workspaces:insert {
          name = "foo",
          meta = {
            color = "#255255",
          }
        })

        local res = assert(client:patch("/workspaces/foo", {
          body = {
            name = "new_foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("Cannot rename a workspace", json.message)
      end)

      it("updates an existing entity", function()
        assert(bp.workspaces:insert {
          name = "upfoo",
        })
        local image = "data:image/png;base64,fakeimage"
        local res = assert(client:patch("/workspaces/upfoo", {
          body   = {
            comment = "foo comment",
            meta = {
              color = "#255255",
              thumbnail = image
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("foo comment", json.comment)
        assert.equals("#255255", json.meta.color)
        assert.equals(image, json.meta.thumbnail)
      end)

      it("creates default files if portal is turned on", function()
        assert(bp.workspaces:insert {
          name = "rad-portal-man",
        })

        -- patch to enable portal
        assert.res_status(200, client:patch("/workspaces/rad-portal-man", {
          body   = {
            config = {
              portal = true
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        helpers.wait_until(function()
          local client = assert(helpers.admin_client())
          local res = assert(client:get("/rad-portal-man/files"))
          if res.status ~= 200 then
            client:close()
            return false
          end
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          client:close()
          return #json.data > 0
        end)
      end)

      it("respects previoulsy set config values on update", function()
        assert(bp.workspaces:insert {
          name = "sweet-portal-dude",
          config = {
            portal = true,
            portal_auth = "basic-auth",
            portal_session_conf = PORTAL_SESSION_CONF,
            portal_auto_approve = true,
          }
        })

        -- patch to update workspace config
        assert.res_status(200, client:patch("/workspaces/sweet-portal-dude", {
          body   = {
            config = {
              portal_auth = "key-auth"
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        local expected_config = {
          portal = true,
          portal_auth = "key-auth",
          portal_auto_approve = true,
        }

        local res = assert(client:get("/workspaces/sweet-portal-dude"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(expected_config.portal, json.config.portal)
        assert.equals(expected_config.portal_auth, json.config.portal_auth)
        assert.equals(expected_config.portal_auto_approve, json.config.portal_auto_approve)
      end)

      it("validates auth type with current auth conf when none is sent with request", function()
        assert(bp.workspaces:insert {
          name = "neat-portal-friend",
          config = {
            portal = true,
            portal_auth = "key-auth",
            portal_auth_conf = {
              ["key_in_body"] = false,
            },
            portal_session_conf = PORTAL_SESSION_CONF
          }
        })

        local res = client:patch("/workspaces/neat-portal-friend", {
          body = {
            config = {
              portal_auth = "basic-auth",
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equals('unknown field', json.message.config.key_in_body)
      end)

      describe("portal_auth_conf", function()

        before_each(function()
          db:truncate("files")
        end)

        it("allows PATCH with 'portal_auth_conf' without 'portal_auth' value", function()
          assert(bp.workspaces:insert {
            name = "rad-portal-dude",
            config = {
              portal = true
            }
          })

          local res = client:patch("/workspaces/rad-portal-dude", {
            body = {
              config = {
                portal_auth_conf = {
                  hide_credentials = true
                }
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(200, res)
        end)

        it("(basic-auth) allows PATCH when setting 'portal_auth' in same call", function()
          assert(bp.workspaces:insert {
            name = "sick-portal-dude",
            config = {
              portal = true
            }
          })

          local res = client:patch("/workspaces/sick-portal-dude", {
            body = {
              config = {
                portal_auth_conf = {
                  hide_credentials = true
                },
                portal_auth = 'basic-auth',
                portal_session_conf = PORTAL_SESSION_CONF
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equals('{"hide_credentials":true}', json.config.portal_auth_conf)
        end)

        it("(basic-auth) allows PATCH with no previous 'portal_auth_conf' value", function()
          assert(bp.workspaces:insert {
            name = "sick-portal-man",
            config = {
              portal = true,
              portal_auth = 'basic-auth',
              portal_session_conf = PORTAL_SESSION_CONF
            }
          })

          local res = client:patch("/workspaces/sick-portal-man", {
            body = {
              config = {
                portal_auth_conf = {
                  hide_credentials = true
                }
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equals('{"hide_credentials":true}', json.config.portal_auth_conf)
        end)

        it("(basic-auth) PATCH overrides previous 'portal_auth_conf' values", function()
          assert(client:post("/workspaces", {
            body = {
              name = "bad-portal-man",
              config = {
                portal_auth = "basic-auth",
                portal_auth_conf = {
                  hide_credentials = true,
                },
                portal_session_conf = PORTAL_SESSION_CONF
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          if client then
            client:close()
          end
          client = assert(helpers.admin_client())

          local res = client:patch("/workspaces/bad-portal-man", {
            body = {
              config = {
                portal_auth_conf = {
                  hide_credentials = false
                }
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equals('{"hide_credentials":false}', json.config.portal_auth_conf)
        end)

        it("(key-auth) PATCH respects previous 'portal_auth_conf' values", function()
          assert(client:post("/workspaces", {
            body = {
              name = "sad-portal-man",
              config = {
                portal_auth = "key-auth",
                portal_auth_conf = {
                  hide_credentials = false,
                  ["key_names"] = { "dog" }
                },
                portal_session_conf = PORTAL_SESSION_CONF
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          if client then
            client:close()
          end

          client = assert(helpers.admin_client())

          local res = client:patch("/workspaces/sad-portal-man", {
            body = {
              config = {
                portal_auth_conf = {
                  hide_credentials = true
                }
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equals(
            '{"hide_credentials":true}',
            json.config.portal_auth_conf
          )
        end)
      end)

      describe("portal_session_conf", function()

        it("(basic-auth) requires portal_session conf when portal_auth is basic-auth", function()
          assert(bp.workspaces:insert {
            name = "rad-portal-girl",
            config = {
              portal = true
            }
          })

          local res = client:patch("/workspaces/rad-portal-girl", {
            body = {
              config = {
                portal_auth = "basic-auth"
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equals("'portal_session_conf' is required when 'portal_auth' is set to basic-auth", json.message)
        end)

        it("(key-auth) requires portal_session conf when portal_auth is key-auth", function()
          assert(bp.workspaces:insert {
            name = "sick-portal-girl",
            config = {
              portal = true
            }
          })

          local res = client:patch("/workspaces/sick-portal-girl", {
            body = {
              config = {
                portal_auth = "key-auth"
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equals("'portal_session_conf' is required when 'portal_auth' is set to key-auth", json.message)
        end)

        it("(nil auth) does not require portal_session conf when portal_auth is not set", function()
          assert(bp.workspaces:insert {
            name = "sweet-portal-fella",
            config = {
              portal = false,
            }
          })

          local res = client:patch("/workspaces/sweet-portal-fella", {
            body = {
              config = {
                portal = true,
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(200, res)
        end)


        it("(null auth) does not require portal_session conf when portal_auth is not set", function()
          assert(bp.workspaces:insert {
            name = "sweet-portal-girl",
            config = {
              portal = false,
            }
          })

          local res = client:patch("/workspaces/sweet-portal-girl", {
            body = {
              config = {
                portal = true,
                portal_auth = ngx.null,
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(200, res)
        end)

        it("(auth off) does not require portal_session conf when portal_auth is not set", function()
          assert(bp.workspaces:insert {
            name = "rad-portal-fella",
            config = {
              portal = false,
            }
          })

          local res = client:patch("/workspaces/rad-portal-fella", {
            body = {
              config = {
                portal = true,
                portal_auth = "",
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(200, res)
        end)

        it("requires portal_session_conf to be a table", function()
          assert(bp.workspaces:insert {
            name = "rad-portal",
            config = {
              portal = true,
            }
          })

          local res = client:patch("/workspaces/rad-portal", {
            body = {
              config = {
                portal_auth = "basic-auth",
                portal_session_conf = "yeet",
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equals("'config.portal_session_conf' must be type 'table'", json.message)
        end)

        it("requires secret to be a string", function()
          assert(bp.workspaces:insert {
            name = "sweet-portal",
            config = {
              portal = true,
            }
          })

          local res = client:patch("/workspaces/sweet-portal", {
            body = {
              config = {
                portal_auth = "basic-auth",
                portal_session_conf = {},
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equals("'config.portal_session_conf.secret' must be type 'string'", json.message)
        end)

        pending("(openid-connect) does not require portal_session conf when portal_auth is openid-connect", function()
          assert(bp.workspaces:insert {
            name = "sick-portal",
            config = {
              portal = true
            }
          })

          local res = client:patch("/workspaces/sick-portal", {
            body = {
              config = {
                portal_auth = "openid-connect",
                portal_auth_conf = {
                  issuer = "https://accounts.google.test/"
                }
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(200, res)
        end)

        it("accepts valid config", function()
          assert(bp.workspaces:insert {
            name = "awesome-portal-man",
            config = {
              portal = true,
            }
          })

          local res = client:patch("/workspaces/awesome-portal-man", {
            body = {
              config = {
                portal_auth = "basic-auth",
                portal_session_conf = {
                  secret = "shh"
                }
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(200, res)
        end)

        it("overrides previous values", function()
          assert(bp.workspaces:insert {
            name = "awesome-portal-dude",
            config = {
              portal = true,
              portal_auth = "basic-auth",
              portal_session_conf = {
                secret = "don't tell anyone"
              }
            }
          })

          local res = client:patch("/workspaces/awesome-portal-dude", {
            body = {
              config = {
                portal_auth = "basic-auth",
                portal_session_conf = PORTAL_SESSION_CONF
              }
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          local session_conf = cjson.decode(json.config.portal_session_conf)

          assert.same(PORTAL_SESSION_CONF, session_conf)
        end)
      end)
    end)

    describe("GET", function()
      it("retrieves the default workspace", function()
        local res = assert(client:send {
          method = "GET",
          path = "/workspaces/" .. workspaces.DEFAULT_WORKSPACE,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(workspaces.DEFAULT_WORKSPACE, json.name)
      end)

      it("retrieves a single workspace", function()
        assert(bp.workspaces:insert {
          name = "foo-fighter",
          meta = {
            color = "#255255",
          }
        })

        local res = assert(client:get("/workspaces/foo-fighter"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("foo-fighter", json.name)
        assert.equals("#255255", json.meta.color)
      end)

      it("retrieves a single workspace that has a name with special chars", function()
        local res = assert(client:get("/workspaces/ws-Áæ"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals("ws-Áæ", json.name)

        -- special chars can be escaped
        local ws_escaped_name = ngx.escape_uri("ws-Áæ")
        local res = assert(client:get("/workspaces/" .. ws_escaped_name))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals("ws-Áæ", json.name)
      end)

      it("can fetch workspace data with encoded uri", function()
        local encoded_ws_name = ngx.escape_uri("ws-Áæ")
        local res = client:get("/" ..  encoded_ws_name .. "/services")
        assert.res_status(200, res)
      end)

      it("sends the appropriate status on an invalid entity", function()
        assert.res_status(404, client:get("/workspaces/baz"))
      end)

      it("returns 404 if we call from another workspace", function()
        assert(bp.workspaces:insert {
          name = "foo2",
        })
        assert.res_status(404, client:get("/foo2/workspaces/default"))
        assert.res_status(200, client:get("/workspaces/foo2"))
        assert.res_status(200, client:get("/default/workspaces/foo2"))
        assert.res_status(200, client:get("/foo2/workspaces/foo2"))
      end)
    end)

    describe("delete", function()
      it("refuses to delete default workspace", function()
        assert.res_status(400, client:delete("/workspaces/default"))
      end)

      it("removes a workspace", function()
        assert(bp.workspaces:insert {
          name = "barbecue",
        })
        assert.res_status(204, client:delete("/workspaces/barbecue"))
      end)

      it("sends the appropriate status on an invalid entity", function()
        assert.res_status(404, client:delete("/workspaces/bar"))
      end)

      it("refuses to delete a non empty workspace", function()
        assert(bp.workspaces:insert {
          name = "footos",
        })

        local res = assert(client:send {
          method = "post",
          path   = "/footos/consumers",
          body = {
            username = "footos"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "delete",
          path   = "/workspaces/footos",
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ message = {
          entities = { consumers = 1 },
          message = "Workspace is not empty",
        }}, json)
      end)
    end)
  end)
end) -- end describe

end -- end for

for _, strategy in helpers.each_strategy() do

describe("Admin API #" .. strategy, function()
  local client
  local bp, db, _

  local function post(path, body, headers, expected_status)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    local res = assert(client:send{
      method = "POST",
      path = path,
      body = body or {},
      headers = headers
    })
    return cjson.decode(assert.res_status(expected_status or 201, res))
  end


  local function put(path, body, headers, expected_status) -- luacheck: ignore
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    local res = assert(client:send{
      method = "PUT",
      path = path,
      body = body or {},
      headers = headers
    })
    return cjson.decode(assert.res_status(expected_status or 200, res))
  end

  lazy_setup(function()
    bp, db, _ = helpers.get_db_utils(strategy)

    local demo_ip_service = bp.services:insert {
      name = "demo-ip",
      protocol = "http",
      host = "test.test",
      path = "/ip",
    }

    bp.routes:insert({
      hosts = {"my.api.test" },
      paths = { "/my-uri" },
      methods = { "GET" },
      service = demo_ip_service,
    })
    -- ]]

    -- create a workspace and add a service in it [[
    local ws = bp.workspaces:insert {
      name = "w1"
    }

    bp.services:insert_ws ({
      name = "demo-anything",
      protocol = "http",
      host = "test.test",
      path = "/anything",
    }, ws)
    -- ]]

    -- add different service to the default workspace
    bp.services:insert {
      name = "demo-default",
      protocol = "http",
      host = "test.test",
      path = "/default",
    }


    assert(helpers.start_kong{
      database = strategy
    })

    client = assert(helpers.admin_client())
  end)
  lazy_teardown(function()
    helpers.stop_kong()
    if client then
      client:close()
    end
  end)

  describe("POST /routes", function()
    describe("Refresh the router", function()
      it("doesn't create a route when it conflicts", function()
        -- create service and route in workspace default [[
        -- route collides with one in default workspace
        assert.res_status(409, client:post("/w1/services/demo-anything/routes", {
          body = {
            hosts = {"my.api.test" },
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        -- allows adding service colliding with another in the same workspace
        assert.res_status(201, client:post("/default/services/demo-default/routes", {
          body = {
            methods = { "GET" },
            hosts = {"my.api.test"},
            paths = { "/my-uri" },
          },
          headers = {["Content-Type"] = "application/json"}
        }))
      end)

      it("doesn't allow creating routes that collide in path and have no host", function()
        assert.res_status(201, client:post("/default/services/demo-ip/routes", {
          body = {
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        assert.res_status(409, client:post("/w1/services/demo-anything/routes", {
          body = {
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))
      end)

      it("route PATCH checks collision", function()
        assert.res_status(201, client:post("/default/services/demo-ip/routes", {
          body = {
            hosts = {"my.api.test" },
            paths = { "/my-path" },
            methods = { "GET" },
          },
          headers = { ["Content-Type"] = "application/json"},
        }))

        local res = client:post("/w1/services/demo-anything/routes", {
          body = {
            hosts = {"my.api.test2" },
            paths = { "/my-path" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        })
        res = cjson.decode(assert.res_status(201, res))

        -- route collides in different WS
        assert.res_status(409, client:patch("/w1/routes/".. res.id, {
          body = {
            hosts = {"my.api.test" },
            paths = { "/my-path" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))
      end)
    end)
  end)

  describe("PUT /consumers", function()
    before_each(function()
      db:truncate("consumers")
    end)

    -- FTI-1874 regression test
    it("uniquifies non-path attributes", function()
      local consumer_data = { custom_id = "c"}
      post("/workspaces", { name="foo"})
      post("/workspaces", { name="bar"})
      put("/foo/consumers/c1", consumer_data)
      put("/bar/consumers/c1", consumer_data)
    end)
  end)

end) -- end describe

end -- end for
