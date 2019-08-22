local helpers     = require "spec.helpers"
local cjson       = require "cjson"
local utils       = require "kong.tools.utils"
local workspaces  = require "kong.workspaces"

local PORTAL_SESSION_CONF = {
  storage = "kong",
  cookie_name = "portal_cookie",
  secret = "shh"
}
for _, strategy in helpers.each_strategy() do

describe("Workspaces Admin API (#" .. strategy .. "): ", function()
  local client,  db, bp

  setup(function()
    bp, db = helpers.get_db_utils(strategy)

    assert(helpers.start_kong({
      database = strategy,
      portal = true,
    }))

    client = assert(helpers.admin_client())
  end)

  before_each(function()
    db:truncate("workspaces")
    db:truncate("workspace_entities")
  end)

  teardown(function()
    if client then
      client:close()
    end

    helpers.stop_kong()
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
          name = "foo",
        })
        local res = assert(client:post("/workspaces", {
          body   = {
            name = "foo",
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

        -- sleep to allow time for threaded file migrations to complete
        ngx.sleep(5)

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.id))
        assert.equals("ws-with-portal", json.name)

        local res = assert(client:get("/ws-with-portal/files"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.truthy(#json.data > 0)
      end)

      describe("portal_auth_conf", function()
        after_each(function()
          db:truncate("files")
          db:truncate("workspaces")
          db:truncate("workspace_entities")
        end)

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
              name = "foo",
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
              name = "foo",
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
              name = "foo",
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

      it("returns 404 if called from other than default workspace", function()
        assert.res_status(404, client:get("/bar/workspaces"))
        assert.res_status(200, client:get("/default/workspaces"))
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
            color = "red",
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
          name = "foo",
        })

        local res = assert(client:patch("/workspaces/foo", {
          body   = {
            comment = "foo comment",
            meta = {
              color = "red",
              thumbnail = "cool"
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        -- sleep to allow time for threaded file migrations to complete
        ngx.sleep(5)

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("foo comment", json.comment)
        assert.equals("red", json.meta.color)
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

        -- sleep to allow time for threaded file migrations to complete
        ngx.sleep(5)

        -- make sure /files exists
        local res = assert(client:get("/rad-portal-man/files"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.truthy(#json.data > 0)
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
          db:truncate("workspaces")
          db:truncate("workspace_entities")
        end)

        it("allows PATCH withv'portal_auth_conf' without 'portal_auth' value", function()
          assert(bp.workspaces:insert {
            name = "rad-portal-man",
            config = {
              portal = true
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
            name = "rad-portal-man",
            config = {
              portal = true
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
            name = "rad-portal-man",
            config = {
              portal = true,
              portal_auth = 'basic-auth',
              portal_session_conf = PORTAL_SESSION_CONF
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
        before_each(function()
          db:truncate("files")
          db:truncate("workspaces")
          db:truncate("workspace_entities")
        end)

        it("(basic-auth) requires portal_session conf when portal_auth is basic-auth", function()
          assert(bp.workspaces:insert {
            name = "rad-portal-man",
            config = {
              portal = true
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
            name = "rad-portal-man",
            config = {
              portal = true
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
            name = "rad-portal-man",
            config = {
              portal = false,
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
            name = "rad-portal-man",
            config = {
              portal = false,
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
            name = "rad-portal-man",
            config = {
              portal = false,
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
            name = "rad-portal-man",
            config = {
              portal = true,
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
            name = "rad-portal-man",
            config = {
              portal = true,
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
            name = "rad-portal-man",
            config = {
              portal = true
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
            body = {
              config = {
                portal_auth = "openid-connect",
                portal_auth_conf = {
                  issuer = "https://accounts.google.com/"
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
            name = "rad-portal-man",
            config = {
              portal = true,
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
            name = "rad-portal-man",
            config = {
              portal = true,
              portal_auth = "basic-auth",
              portal_session_conf = {
                secret = "don't tell anyone"
              }
            }
          })

          local res = client:patch("/workspaces/rad-portal-man", {
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
          name = "foo",
          meta = {
            color = "red",
          }
        })

        local res = assert(client:get("/workspaces/foo"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("foo", json.name)
        assert.equals("red", json.meta.color)
      end)

      it("sends the appropriate status on an invalid entity", function()
        assert.res_status(404, client:get("/workspaces/baz"))
      end)

      it("returns 404 if we call from another workspace", function()
        assert(bp.workspaces:insert {
          name = "foo",
        })
        assert.res_status(404, client:get("/foo/workspaces/default"))
        assert.res_status(200, client:get("/workspaces/foo"))
        assert.res_status(200, client:get("/default/workspaces/foo"))
        assert.res_status(200, client:get("/foo/workspaces/foo"))
      end)
    end)

    describe("delete", function()
      it("refuses to delete default workspace", function()
        assert.res_status(400, client:delete("/workspaces/default"))
      end)

      it("removes a workspace", function()
        assert(bp.workspaces:insert {
          name = "bar",
        })
        assert.res_status(204, client:delete("/workspaces/bar"))
      end)

      it("sends the appropriate status on an invalid entity", function()
        assert.res_status(404, client:delete("/workspaces/bar"))
      end)

      it("refuses to delete a non empty workspace", function()
        local ws = assert(bp.workspaces:insert {
          name = "foo",
        })
        bp.services:insert_ws({}, ws)

        local res = assert(client:send {
          method = "delete",
          path   = "/workspaces/foo",
        })
        assert.res_status(400, res)
      end)
    end)
  end)

  describe("/workspaces/:workspace/entites", function()
    describe("GET", function()
      it("returns a list of entities associated with the default workspace", function()
        local res = assert(client:send{
          method = "GET",
          path = "/workspaces/default/entities",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- no entity associated with it by default
        -- previously, when workspaces were workspaceable, the count was 2,
        -- given default was in default, and each entity adds two rows in
        -- workspace_entities
        assert.equals(0, #json.data)
      end)

      it("returns a list of entities associated with the workspace", function()
        assert(bp.workspaces:insert {
          name = "foo"
        })
        -- create some entities
        local consumers = bp.consumers:insert_n(10)

        -- share them
        for _, consumer in ipairs(consumers) do
          assert.res_status(201, client:post("/workspaces/foo/entities", {
            body = {
              entities = consumer.id
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))
        end

        local res = assert(client:send {
          method = "GET",
          path = "/workspaces/foo/entities",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert(10, #json.data)
        for _, entity in ipairs(json.data) do
          assert.same("consumers", entity.entity_type)
        end
      end)
    end)

    describe("POST", function()
      describe("handles errors", function()
        it("on duplicate association", function()
          assert(bp.workspaces:insert {
            name = "foo"
          })
          local consumer = assert(bp.consumers:insert())

          local res = assert(client:post("/workspaces/foo/entities", {
            body = {
              entities = consumer.id,
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))
          assert.res_status(201, res)

          local res = assert(client:post("/workspaces/foo/entities", {
            body = {
              entities = consumer.id,
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))
          local json = cjson.decode(assert.res_status(409, res))
          assert.matches("Entity '" .. consumer.id .. "' " ..
                         "already associated with workspace", json.message, nil,
                         true)
        end)

        it("on invalid UUID", function()
          assert(bp.workspaces:insert {
            name = "foo"
          })

          local res = assert(client:post("/workspaces/foo/entities", {
            body = {
              entities = "nop",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equals("'nop' is not a valid UUID", json.message)
        end)

        it("without inserting some valid rows prior to failure", function()
          local ws = assert(bp.workspaces:insert {
            name = "foo"
          })

          local n = db.workspace_entities:select_all({
            workspace_id = ws.id
          })
          n = #n

          local res = assert(client:post("/workspaces/foo/entities", {
            body = {
              entities = utils.uuid() .. ",nop",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equals("'nop' is not a valid UUID", json.message)

          local new_n = db.workspace_entities:select_all({
            workspace_id = ws.id
          })
          new_n = #new_n
          assert.same(n, new_n)
        end)
      end)
    end)

    describe("DELETE", function()
      it("fails to remove an unexisting entity relationship", function()
        assert.res_status(404, client:send {
          method = "DELETE",
          path = "/workspaces/foo/entities",
          body = {
            entities = utils.uuid()
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
      end)

      it("does not leave dangling entities (old dao)", function()
        -- create a workspace
        assert(bp.workspaces:insert({
          name = "foo",
        }))
        -- create a consumer
        local consumer = assert(bp.consumers:insert())

        -- share with workspace foo
        assert.res_status(201, client:post("/workspaces/foo/entities", {
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        -- now, delete the entity from foo
        assert.res_status(204, client:delete("/workspaces/foo/entities", {
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        -- and delete it from default, too
        assert.res_status(204, client:delete("/workspaces/default/entities", {
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        -- the entity must be gone - as it was deleted from both workspaces
        -- it belonged to
        local res, err = db.consumers:select({
          id = consumer.id
        })
        assert.is_nil(err)
        assert.is_nil(res)

        -- and we must be able to create an entity with that same name again
        assert.res_status(201, client:send {
          method = "POST",
          path = "/consumers",
          body = {
            username = "foosumer"
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
      end)

      it("removes a relationship", function()
        -- create a workspace
        assert(bp.workspaces:insert({
          name = "foo",
        }))
        -- create a consumer
        local consumer = assert(bp.consumers:insert())

        -- share with workspace foo
        assert.res_status(201, client:post("/workspaces/foo/entities", {
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        -- now, delete the entity from foo
        assert.res_status(204, client:send {
          method = "DELETE",
          path = "/workspaces/foo/entities",
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        -- now, delete the entity from foo
        local json = cjson.decode(assert.res_status(200, client:get("/workspaces/foo/entities", {
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })))

        assert.truthy(#json.data == 0)
      end)

      it("sends the appropriate status on an invalid entity", function()
        assert(bp.workspaces:insert({
          name = "foo",
        }))
        assert.res_status(404, client:delete("/workspaces/foo/entities", {
          body = {
            entities = utils.uuid(),
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))
      end)
    end)
  end)

  describe("/workspaces/:workspace/entites/:entity", function()
    describe("GET", function()
      it("returns a single relation representation", function()
        -- create a workspace
        local ws = assert(bp.workspaces:insert({
          name = "foo",
        }))
        -- create a consumer
        local consumer = assert(bp.consumers:insert_ws(nil, ws))

        local res = assert(client:send {
          method = "GET",
          path = "/workspaces/foo/entities/" .. consumer.id,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(json.workspace_id, ws.id)
        assert.equals(json.entity_id, consumer.id)
        assert.equals(json.entity_type, "consumers")
      end)

      it("sends the appropriate status on an invalid entity", function()
        -- create a workspace
        assert(bp.workspaces:insert({
          name = "foo",
        }))

        assert.res_status(404, client:send {
          method = "GET",
          path = "/workspaces/foo/entities/" .. utils.uuid(),
        })
      end)
    end)

    describe("DELETE", function()
      it("removes a single relation representation", function()
        -- create a workspace
        local ws = assert(bp.workspaces:insert({
          name = "foo",
        }))
        -- create a consumer
        local consumer = assert(bp.consumers:insert_ws(nil, ws))

        assert.res_status(204, client:send({
          method = "DELETE",
          path = "/workspaces/foo/entities/" .. consumer.id,
        }))
      end)

      it("sends the appropriate status on an invalid entity", function()
        assert(bp.workspaces:insert({
          name = "foo",
        }))
        assert.res_status(404, client:send {
          method = "DELETE",
          path = "/workspaces/foo/entities/" .. utils.uuid(),
        })
      end)
    end)
  end)
end) -- end describe

end -- end for

for _, strategy in helpers.each_strategy() do

describe("Admin API #" .. strategy, function()
  local client
  local bp, db, _
  setup(function()
    bp, db, _ = helpers.get_db_utils(strategy)

    assert(helpers.start_kong{
      database = strategy
    })

    client = assert(helpers.admin_client())
  end)
  teardown(function()
    helpers.stop_kong()
    if client then
      client:close()
    end
  end)

  describe("POST /routes", function()
    describe("Refresh the router", function()
      before_each(function()
        db:truncate("services")
        db:truncate("routes")
        db:truncate("workspaces")
        db:truncate("workspace_entities")
      end)

      it("doesn't create a route when it conflicts", function()
        -- create service and route in workspace default [[
        local demo_ip_service = bp.services:insert {
          name = "demo-ip",
          protocol = "http",
          host = "httpbin.org",
          path = "/ip",
        }

        bp.routes:insert({
          hosts = {"my.api.com" },
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
          host = "httpbin.org",
          path = "/anything",
        }, ws)
        -- ]]

        -- route collides with one in default workspace
        assert.res_status(409, client:post("/w1/services/demo-anything/routes", {
          body = {
            hosts = {"my.api.com" },
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        -- add different service to the default workspace
        bp.services:insert {
          name = "demo-default",
          protocol = "http",
          host = "httpbin.org",
          path = "/default",
        }

        -- allows adding service colliding with another in the same workspace
        assert.res_status(201, client:post("/default/services/demo-default/routes", {
          body = {
            methods = { "GET" },
            hosts = {"my.api.com"},
            paths = { "/my-uri" },
          },
          headers = {["Content-Type"] = "application/json"}
        }))
      end)

      it("doesn't allow creating routes that collide in path and have no host", function()
        local ws_name = utils.uuid()
        local ws = bp.workspaces:insert {
          name = ws_name
        }

        bp.services:insert {
          name = "demo-ip",
          protocol = "http",
          host = "httpbin.org",
          path = "/ip",
        }

        bp.services:insert_ws ({
          name = "demo-anything",
          protocol = "http",
          host = "httpbin.org",
          path = "/anything",
        }, ws)

        assert.res_status(201, client:post("/default/services/demo-ip/routes", {
          body = {
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        assert.res_status(409, client:post("/".. ws_name.."/services/demo-anything/routes", {
          body = {
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))
      end)

      it("route PATCH checks collision", function()
        local ws_name = utils.uuid()
        local ws = bp.workspaces:insert {
          name = ws_name
        }

        bp.services:insert {
          name = "demo-ip",
          protocol = "http",
          host = "httpbin.org",
          path = "/ip",
        }

        bp.services:insert_ws ({
          name = "demo-anything",
          protocol = "http",
          host = "httpbin.org",
          path = "/anything",
        }, ws)

        assert.res_status(201, client:post("/default/services/demo-ip/routes", {
          body = {
            hosts = {"my.api.com" },
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = { ["Content-Type"] = "application/json"},
        }))

        local res = client:post("/" .. ws_name .. "/services/demo-anything/routes", {
          body = {
            hosts = {"my.api.com2" },
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        })
        res = cjson.decode(assert.res_status(201, res))

        -- route collides in different WS
        assert.res_status(409, client:patch("/" .. ws_name .. "/routes/".. res.id, {
          body = {
            hosts = {"my.api.com" },
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))
      end)
    end)
  end)
end) -- end describe

end -- end for
