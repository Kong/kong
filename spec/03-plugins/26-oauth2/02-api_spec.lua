local cjson   = require "cjson"
local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: oauth (API) [#" .. strategy .. "]", function()
    local consumer
    local service
    local admin_client
    local db
    local bp

    setup(function()
      bp, db = helpers.get_db_utils(strategy)

      assert(db:truncate("routes"))
      assert(db:truncate("services"))
      assert(db:truncate("consumers"))
      assert(db:truncate("oauth2_tokens"))
      assert(db:truncate("oauth2_authorization_codes"))
      assert(db:truncate("oauth2_credentials"))
      assert(db:truncate("plugins"))

      helpers.prepare_prefix()

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      admin_client = helpers.admin_client()
    end)
    teardown(function()
      if admin_client then admin_client:close() end
      assert(helpers.stop_kong())
      helpers.clean_prefix()
    end)

    describe("/consumers/:consumer/oauth2/", function()
      setup(function()
        service = bp.services:insert({ host = "oauth2_token.com" })
        consumer = bp.consumers:insert({ username = "bob" })
        bp.consumers:insert({ username = "sally" })
      end)

      after_each(function()
        assert(db:truncate("oauth2_credentials"))
      end)

      describe("POST", function()
        it("creates a oauth2 credential", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/oauth2",
            body    = {
              name          = "Test APP",
              redirect_uris = { "http://google.com/" },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.equal(consumer.id, body.consumer.id)
          assert.equal("Test APP", body.name)
          assert.same({ "http://google.com/" }, body.redirect_uris)
        end)
        it("creates a oauth2 credential with multiple redirect_uris", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/oauth2",
            body    = {
              name          = "Test APP",
              redirect_uris = { "http://google.com/", "http://google.org/" },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.equal(consumer.id, body.consumer.id)
          assert.equal("Test APP", body.name)
          assert.same({ "http://google.com/", "http://google.org/" }, body.redirect_uris)
        end)
        it("creates multiple oauth2 credentials with the same client_secret", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/oauth2",
            body    = {
              name          = "Test APP",
              redirect_uris = { "http://google.com/" },
              client_secret = "secret123",
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
          res = assert(admin_client:send {
            method = "POST",
            path   = "/consumers/sally/oauth2",
            body   = {
              name          = "Test APP",
              redirect_uris = { "http://google.com/" },
              client_secret = "secret123",
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
        end)
        describe("errors", function()
          it("returns bad request", function()
            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/consumers/bob/oauth2",
              body    = {},
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ redirect_uris = "required field missing", name = "required field missing" }, json.fields)
          end)
          it("returns bad request with invalid redirect_uris", function()
            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/consumers/bob/oauth2",
              body    = {
                name             = "Test APP",
                redirect_uris    = { "not-valid" }
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ redirect_uris = "cannot parse 'not-valid'" }, json.fields)

            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/consumers/bob/oauth2",
              body    = {
                name            = "Test APP",
                redirect_uris   = { "http://test.com/#with-fragment" },
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ redirect_uris = "fragment not allowed in 'http://test.com/#with-fragment'" }, json.fields)

            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/consumers/bob/oauth2",
              body    = {
                name             = "Test APP",
                redirect_uris    = {"http://valid.com", "not-valid"}
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ redirect_uris = "cannot parse 'not-valid'" }, json.fields)

            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/consumers/bob/oauth2",
              body    = {
                name             = "Test APP",
                redirect_uris    = {"http://valid.com", "http://test.com/#with-fragment"}
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ redirect_uris = "fragment not allowed in 'http://test.com/#with-fragment'" }, json.fields)
          end)
        end)
      end)

      describe("PUT", function()
        it("creates an oauth2 credential", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/bob/oauth2/client_one",
            body = {
              name             = "Test APP",
              redirect_uris    = { "http://google.com/" },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.equal(consumer.id, body.consumer.id)
          assert.equal("Test APP", body.name)
          assert.equal("client_one", body.client_id)
          assert.same({ "http://google.com/" }, body.redirect_uris)
        end)
        describe("errors", function()
          it("returns bad request", function()
            local res = assert(admin_client:send {
              method  = "PUT",
              path    = "/consumers/bob/oauth2/client_two",
              body    = {},
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ redirect_uris = "required field missing", name = "required field missing" }, json.fields)
          end)
        end)
      end)

      describe("GET", function()
        setup(function()
          for i = 1, 3 do
            bp.oauth2_credentials:insert {
              name          = "app" .. i,
              redirect_uris = { helpers.mock_upstream_ssl_url },
              consumer      = { id = consumer.id },
            }
          end
        end)
        teardown(function()
          assert(db:truncate("oauth2_credentials"))
        end)
        it("retrieves the first page", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/oauth2"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(3, #json.data)
        end)
      end)
    end)

    describe("/consumers/:consumer/oauth2/:id", function()
      local credential
      before_each(function()
        assert(db:truncate("oauth2_credentials"))
        assert(db:truncate("routes"))
        assert(db:truncate("services"))
        assert(db:truncate("consumers"))

        service = bp.services:insert({ host = "oauth2_token.com" })
        consumer = bp.consumers:insert({ username = "bob" })
        credential = bp.oauth2_credentials:insert {
          name          = "test app",
          redirect_uris = { helpers.mock_upstream_ssl_url },
          consumer      = { id = consumer.id },
        }
      end)
      describe("GET", function()
        it("retrieves oauth2 credential by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/oauth2/" .. credential.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(credential.id, json.id)
        end)
        it("retrieves oauth2 credential by client id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/oauth2/" .. credential.client_id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(credential.id, json.id)
        end)
        it("retrieves credential by id only if the credential belongs to the specified consumer", function()
          bp.consumers:insert {
            username = "alice"
          }

          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/oauth2/" .. credential.id
          })
          assert.res_status(200, res)

          res = assert(admin_client:send {
            method = "GET",
            path   = "/consumers/alice/oauth2/" .. credential.id
          })
          assert.res_status(404, res)
        end)
        it("retrieves credential by clientid only if the credential belongs to the specified consumer", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/oauth2/" .. credential.client_id
          })
          assert.res_status(200, res)

          res = assert(admin_client:send {
            method = "GET",
            path   = "/consumers/alice/oauth2/" .. credential.client_id
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        it("updates a credential by id", function()
          local previous_name = credential.name

          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/bob/oauth2/" .. credential.id,
            body    = {
              name             = "4321"
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
            method  = "PATCH",
            path    = "/consumers/bob/oauth2/" .. credential.client_id,
            body    = {
              name             = "4321UDP"
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
              method  = "PATCH",
              path    = "/consumers/bob/oauth2/" .. credential.id,
              body    = {
                redirect_uris = { "not-valid" },
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ redirect_uris = "cannot parse 'not-valid'" }, json.fields)
          end)
        end)
      end)

      describe("DELETE", function()
        it("deletes a credential", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/bob/oauth2/" .. credential.id,
          })
          assert.res_status(204, res)
        end)
        describe("errors", function()
          it("returns 400 on invalid input", function()
            local res = assert(admin_client:send {
              method  = "DELETE",
              path    = "/consumers/bob/oauth2/blah"
            })
            assert.res_status(404, res)
          end)
          it("returns 404 if not found", function()
            local res = assert(admin_client:send {
              method  = "DELETE",
              path    = "/consumers/bob/oauth2/00000000-0000-0000-0000-000000000000"
            })
            assert.res_status(404, res)
          end)
        end)
      end)
    end)

    describe("/oauth2_tokens/", function()
      local oauth2_credential
      setup(function()
        oauth2_credential = bp.oauth2_credentials:insert {
          name          = "Test APP",
          redirect_uris = { helpers.mock_upstream_ssl_url },
          consumer      = { id = consumer.id },
        }
      end)
      after_each(function()
        assert(db:truncate("oauth2_tokens"))
      end)

      describe("POST", function()
        it("creates a oauth2 token", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/oauth2_tokens",
            body    = {
              credential = { id = oauth2_credential.id },
              service    = { id = service.id },
              expires_in = 10
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.equal(oauth2_credential.id, body.credential.id)
          assert.equal(10, body.expires_in)
          assert.truthy(body.access_token)
          assert.truthy(body.service.id)
          assert.same(ngx.null, body.refresh_token)
          assert.equal("bearer", body.token_type)
        end)
        describe("errors", function()
          it("returns bad request", function()
            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/oauth2_tokens",
              body    = {},
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ expires_in = "required field missing" }, json.fields)
          end)
        end)
      end)

      describe("GET", function()
        setup(function()
          for _ = 1, 3 do
            bp.oauth2_tokens:insert {
              credential = { id = oauth2_credential.id },
              service    = { id = service.id },
              expires_in = 10
            }
          end
        end)
        teardown(function()
          assert(db:truncate("oauth2_tokens"))
        end)
        it("retrieves the first page", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/oauth2_tokens"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(3, #json.data)
        end)
      end)

      describe("/oauth2_tokens/:id", function()
        local token
        before_each(function()
          assert(db:truncate("oauth2_tokens"))
          token = db.oauth2_tokens:insert {
            credential = { id = oauth2_credential.id },
            service    = { id = service.id },
            expires_in = 10
          }
        end)

        describe("GET", function()
          it("retrieves oauth2 token by id", function()
            local res = assert(admin_client:send {
              method  = "GET",
              path    = "/oauth2_tokens/" .. token.id
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(token.id, json.id)
          end)
          it("retrieves oauth2 token by access_token", function()
            local res = assert(admin_client:send {
              method  = "GET",
              path    = "/oauth2_tokens/" .. token.access_token
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(token.id, json.id)
          end)
        end)

        describe("PUT", function()
          it("creates an oauth2 credential", function()
            local res = assert(admin_client:send {
              method  = "PUT",
              path    = "/oauth2_tokens/foobar",
              body    = {
                credential = { id = oauth2_credential.id },
                service    = { id = service.id },
                expires_in = 10
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = cjson.decode(assert.res_status(200, res))
            assert.equal(oauth2_credential.id, body.credential.id)
            assert.equal(10, body.expires_in)
            assert.equal("foobar", body.access_token)
            assert.equal(ngx.null, body.refresh_token)
            assert.equal("bearer", body.token_type)
          end)
          describe("errors", function()
            it("returns bad request", function()
              local res = assert(admin_client:send {
                method  = "PUT",
                path    = "/oauth2_tokens/foobar",
                body    = {},
                headers = {
                  ["Content-Type"] = "application/json"
                }
              })
              local body = assert.res_status(400, res)
              local json = cjson.decode(body)
              assert.same({ expires_in = "required field missing" }, json.fields)
            end)
          end)
        end)

        describe("PATCH", function()
          it("updates a token by id", function()
            local previous_expires_in = token.expires_in

            local res = assert(admin_client:send {
              method  = "PATCH",
              path    = "/oauth2_tokens/" .. token.id,
              body    = {
                expires_in       = 20
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
              method  = "PATCH",
              path    = "/oauth2_tokens/" .. token.access_token,
              body   = {
                expires_in       = 400
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
                method  = "PATCH",
                path    = "/oauth2_tokens/" .. token.id,
                body    = {
                  expires_in       = "hello"
                },
                headers = {
                  ["Content-Type"] = "application/json"
                }
              })
              local body = assert.res_status(400, res)
              local json = cjson.decode(body)
              assert.same({ expires_in = "expected an integer" }, json.fields)
            end)
          end)
        end)

        describe("DELETE", function()
          it("deletes a token", function()
            local res = assert(admin_client:send {
              method  = "DELETE",
              path    = "/oauth2_tokens/" .. token.id,
            })
            assert.res_status(204, res)
          end)
          describe("errors", function()
            it("returns 204 on inexisting tokens", function()
              local res = assert(admin_client:send {
                method  = "DELETE",
                path    = "/oauth2_tokens/blah"
              })
              assert.res_status(204, res)

              local res = assert(admin_client:send {
                method  = "DELETE",
                path    = "/oauth2_tokens/00000000-0000-0000-0000-000000000000"
              })
              assert.res_status(204, res)
            end)
          end)
        end)
      end)
    end)
  end)
end
