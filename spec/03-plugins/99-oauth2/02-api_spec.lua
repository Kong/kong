local cjson = require "cjson"
local helpers = require "spec.helpers"

describe("Plugin: oauth (API)", function()
  local consumer, api, admin_client
  setup(function()
    helpers.prepare_prefix()
    assert(helpers.start_kong())

    admin_client = helpers.admin_client()
  end)
  teardown(function()
    if admin_client then admin_client:close() end
    assert(helpers.stop_kong())
    helpers.clean_prefix()
  end)

  describe("/consumers/:consumer/oauth2/", function()
    setup(function()
      api = assert(helpers.dao.apis:insert {
        name = "oauth2_token.com",
        hosts = { "oauth2_token.com" },
        upstream_url = "http://mockbin.com/"
      })
      consumer = assert(helpers.dao.consumers:insert {
        username = "bob"
      })
    end)
    after_each(function()
      helpers.dao:truncate_table("oauth2_credentials")
    end)

    describe("POST", function()
      it("creates a oauth2 credential", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/oauth2",
          body = {
            name = "Test APP",
            redirect_uri = "http://google.com/"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(consumer.id, body.consumer_id)
        assert.equal("Test APP", body.name)
        assert.equal("http://google.com/", body.redirect_uri[1])
      end)
      it("creates a oauth2 credential with multiple redirect_uri", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/oauth2",
          body = {
            name = "Test APP",
            redirect_uri = "http://google.com/, http://google.org/"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(consumer.id, body.consumer_id)
        assert.equal("Test APP", body.name)
        assert.equal(2, #body.redirect_uri)
      end)
      it("creates an oauth2 credential with allowed_scopes", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/oauth2",
          body = {
            name = "Test APP",
            redirect_uri = "http://google.org/",
            allowed_scopes = "foo bar code"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(consumer.id, body.consumer_id)
        assert.equal("Test APP", body.name)
        assert.equal("foo bar code", body.allowed_scopes)
      end)
      it("creates an oauth2 credential without allowed_scopes", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/oauth2",
          body = {
            name = "Test APP",
            redirect_uri = "http://google.org/"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(consumer.id, body.consumer_id)
        assert.equal("Test APP", body.name)
        assert.is_nil(body.allowed_scopes)
      end)
      describe("errors", function()
        it("returns bad request", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/bob/oauth2",
            body = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"redirect_uri":"redirect_uri is required","name":"name is required"}]], body)
        end)
        it("returns bad request with invalid redirect_uri", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/bob/oauth2",
            body = {
              name = "Test APP",
              redirect_uri = "not-valid"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"redirect_uri":"cannot parse 'not-valid'"}]], body)

          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/bob/oauth2",
            body = {
              name = "Test APP",
              redirect_uri = "http://test.com/#with-fragment"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"redirect_uri":"fragment not allowed in 'http:\/\/test.com\/#with-fragment'"}]], body)

          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/bob/oauth2",
            body = {
              name = "Test APP",
              redirect_uri = {"http://valid.com", "not-valid"}
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"redirect_uri":"cannot parse 'not-valid'"}]], body)

          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/bob/oauth2",
            body = {
              name = "Test APP",
              redirect_uri = {"http://valid.com", "http://test.com/#with-fragment"}
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"redirect_uri":"fragment not allowed in 'http:\/\/test.com\/#with-fragment'"}]], body)
        end)
      end)
    end)

    describe("PUT", function()
      it("creates an oauth2 credential", function()
        local res = assert(admin_client:send {
          method = "PUT",
          path = "/consumers/bob/oauth2",
          body = {
            name = "Test APP",
            redirect_uri = "http://google.com/"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(consumer.id, body.consumer_id)
        assert.equal("Test APP", body.name)
        assert.equal("http://google.com/", body.redirect_uri[1])
      end)
      describe("errors", function()
        it("returns bad request", function()
          local res = assert(admin_client:send {
            method = "PUT",
            path = "/consumers/bob/oauth2",
            body = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"redirect_uri":"redirect_uri is required","name":"name is required"}]], body)
        end)
      end)
    end)

    describe("GET", function()
      setup(function()
        for i = 1, 3 do
          assert(helpers.dao.oauth2_credentials:insert {
            name = "app"..i,
            redirect_uri = "https://mockbin.org",
            consumer_id = consumer.id
          })
        end
      end)
      teardown(function()
        helpers.dao:truncate_table("oauth2_credentials")
      end)
      it("retrieves the first page", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/oauth2"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(3, #json.data)
        assert.equal(3, json.total)
      end)
    end)
  end)

  describe("/consumers/:consumer/oauth2/:id", function()
    local credential
    before_each(function()
      helpers.dao:truncate_table("oauth2_credentials")
      credential = assert(helpers.dao.oauth2_credentials:insert {
        name = "test app",
        redirect_uri = "https://mockbin.org",
        consumer_id = consumer.id
      })
    end)
    describe("GET", function()
      it("retrieves oauth2 credential by id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/oauth2/"..credential.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(credential.id, json.id)
      end)
      it("retrieves oauth2 credential by client id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/oauth2/"..credential.client_id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(credential.id, json.id)
      end)
      it("retrieves credential by id only if the credential belongs to the specified consumer", function()
        assert(helpers.dao.consumers:insert {
          username = "alice"
        })

        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/oauth2/"..credential.id
        })
        assert.res_status(200, res)

        res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/alice/oauth2/"..credential.id
        })
        assert.res_status(404, res)
      end)
      it("retrieves credential by clientid only if the credential belongs to the specified consumer", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/oauth2/"..credential.client_id
        })
        assert.res_status(200, res)

        res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/alice/oauth2/"..credential.client_id
        })
        assert.res_status(404, res)
      end)
    end)

    describe("PATCH", function()
      it("updates a credential by id", function()
        local previous_name = credential.name

        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/oauth2/"..credential.id,
          body = {
            name = "4321"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.not_equal(previous_name, json.name)
      end)
      it("updates a credential by client id", function()
        local previous_name = credential.name

        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/oauth2/"..credential.client_id,
          body = {
            name = "4321UDP"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.not_equal(previous_name, json.name)
      end)
      describe("errors", function()
        it("handles invalid input", function()
          local res = assert(admin_client:send {
            method = "PATCH",
            path = "/consumers/bob/oauth2/"..credential.id,
            body = {
              redirect_uri = "not-valid"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"redirect_uri":"cannot parse 'not-valid'"}]], body)
        end)
      end)
    end)

    describe("DELETE", function()
      it("deletes a credential", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/oauth2/"..credential.id,
        })
        assert.res_status(204, res)
      end)
      describe("errors", function()
        it("returns 400 on invalid input", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/consumers/bob/oauth2/blah"
          })
          assert.res_status(404, res)
        end)
        it("returns 404 if not found", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/consumers/bob/oauth2/00000000-0000-0000-0000-000000000000"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)

  describe("/oauth2_tokens/", function()
    local oauth2_credential
    setup(function()
      oauth2_credential = assert(helpers.dao.oauth2_credentials:insert {
        name = "Test APP",
        redirect_uri = "https://mockin.com",
        consumer_id = consumer.id
      })
    end)
    after_each(function()
      helpers.dao:truncate_table("oauth2_tokens")
    end)

    describe("POST", function()
      it("creates a oauth2 token", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/oauth2_tokens",
          body = {
            credential_id = oauth2_credential.id,
            api_id = api.id,
            expires_in = 10
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(oauth2_credential.id, body.credential_id)
        assert.equal(10, body.expires_in)
        assert.truthy(body.access_token)
        assert.truthy(body.api_id)
        assert.falsy(body.refresh_token)
        assert.equal("bearer", body.token_type)
      end)
      describe("errors", function()
        it("returns bad request", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/oauth2_tokens",
            body = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"credential_id":"credential_id is required","expires_in":"expires_in is required"}]], body)
        end)
      end)
    end)

    describe("PUT", function()
      it("creates an oauth2 credential", function()
        local res = assert(admin_client:send {
          method = "PUT",
          path = "/oauth2_tokens",
          body = {
            credential_id = oauth2_credential.id,
            api_id = api.id,
            expires_in = 10
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(oauth2_credential.id, body.credential_id)
        assert.equal(10, body.expires_in)
        assert.truthy(body.access_token)
        assert.falsy(body.refresh_token)
        assert.equal("bearer", body.token_type)
      end)
      describe("errors", function()
        it("returns bad request", function()
          local res = assert(admin_client:send {
            method = "PUT",
            path = "/oauth2_tokens",
            body = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"credential_id":"credential_id is required","expires_in":"expires_in is required"}]], body)
        end)
      end)
    end)

    describe("GET", function()
      setup(function()
        for _ = 1, 3 do
          assert(helpers.dao.oauth2_tokens:insert {
            credential_id = oauth2_credential.id,
            api_id = api.id,
            expires_in = 10
          })
        end
      end)
      teardown(function()
        helpers.dao:truncate_table("oauth2_tokens")
      end)
      it("retrieves the first page", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/oauth2_tokens"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(3, #json.data)
        assert.equal(3, json.total)
      end)
    end)

    describe("/oauth2_tokens/:id", function()
      local token
      before_each(function()
        helpers.dao:truncate_table("oauth2_tokens")
        token = assert(helpers.dao.oauth2_tokens:insert {
          credential_id = oauth2_credential.id,
          api_id = api.id,
          expires_in = 10
        })
      end)

      describe("GET", function()
        it("retrieves oauth2 token by id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/oauth2_tokens/"..token.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(token.id, json.id)
        end)
        it("retrieves oauth2 token by access_token", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/oauth2_tokens/"..token.access_token
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(token.id, json.id)
        end)
      end)

      describe("PATCH", function()
        it("updates a token by id", function()
          local previous_expires_in = token.expires_in

          local res = assert(admin_client:send {
            method = "PATCH",
            path = "/oauth2_tokens/"..token.id,
            body = {
              expires_in = 20
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.not_equal(previous_expires_in, json.expires_in)
        end)
        it("updates a token by access_token", function()
          local previous_expires_in = token.expires_in

          local res = assert(admin_client:send {
            method = "PATCH",
            path = "/oauth2_tokens/"..token.access_token,
            body = {
              expires_in = 400
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.not_equal(previous_expires_in, json.expires_in)
        end)
        describe("errors", function()
          it("handles invalid input", function()
            local res = assert(admin_client:send {
              method = "PATCH",
              path = "/oauth2_tokens/"..token.id,
              body = {
                expires_in = "hello"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            assert.equal([[{"expires_in":"expires_in is not a number"}]], body)
          end)
        end)
      end)

      describe("DELETE", function()
        it("deletes a token", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/oauth2_tokens/"..token.id,
          })
          assert.res_status(204, res)
        end)
        describe("errors", function()
          it("returns 400 on invalid input", function()
            local res = assert(admin_client:send {
              method = "DELETE",
              path = "/oauth2_tokens/blah"
            })
            assert.res_status(404, res)
          end)
          it("returns 404 if not found", function()
            local res = assert(admin_client:send {
              method = "DELETE",
              path = "/oauth2_tokens/00000000-0000-0000-0000-000000000000"
            })
            assert.res_status(404, res)
          end)
        end)
      end)
    end)
  end)
end)