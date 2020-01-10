local cjson   = require "cjson"
local helpers = require "spec.helpers"
local admin_api = require "spec.fixtures.admin_api"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: oauth (API) [#" .. strategy .. "]", function()
    local admin_client
    local db

    lazy_setup(function()
      local _
      _, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "consumers",
        "plugins",
        "oauth2_tokens",
        "oauth2_authorization_codes",
        "oauth2_credentials",
      })

      helpers.prepare_prefix()

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      assert(helpers.stop_kong())
      helpers.clean_prefix()
    end)

    describe("/consumers/:consumer/oauth2/", function()
      local consumer
      local service

      lazy_setup(function()
        service = admin_api.services:insert({ host = "oauth2_token.com" })
        consumer = admin_api.consumers:insert({ username = "bob" })
        admin_api.consumers:insert({ username = "sally" })
      end)

      lazy_teardown(function()
        admin_api.consumers:remove(consumer)
        admin_api.services:remove(service)
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

          res = assert(admin_client:send {
            method = "POST",
            path   = "/consumers/bob/oauth2",
            body   = {
              name          = "Test APP",
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.equal(consumer.id, body.consumer.id)
          assert.equal("Test APP", body.name)
          assert.same(ngx.null, body.redirect_uris)
        end)
        it("creates an oauth2 credential with tags", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/oauth2",
            body    = {
              name          = "Tags APP",
              redirect_uris = { "http://example.com/" },
              tags = { "tag1", "tag2" },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal(consumer.id, json.consumer.id)
          assert.equal("tag1", json.tags[1])
          assert.equal("tag2", json.tags[2])
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
            assert.same({ name = "required field missing" }, json.fields)
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
            assert.same({ redirect_uris = { "cannot parse 'not-valid'" } }, json.fields)

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
            assert.same({ redirect_uris = { "fragment not allowed in 'http://test.com/#with-fragment'" } }, json.fields)

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
            assert.same({ redirect_uris = { ngx.null, "cannot parse 'not-valid'" } }, json.fields)

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
            assert.same({ redirect_uris = {
                            ngx.null,
                            "fragment not allowed in 'http://test.com/#with-fragment'"
                        } }, json.fields)
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

          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/bob/oauth2/client_one",
            body = {
              name             = "Test APP",
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.equal(consumer.id, body.consumer.id)
          assert.equal("Test APP", body.name)
          assert.equal("client_one", body.client_id)
          assert.same(ngx.null, body.redirect_uris)
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
            assert.same({ name = "required field missing" }, json.fields)
          end)
        end)
      end)

      describe("GET", function()
        local consumer = admin_api.consumers:insert({
          username = "get_test",
        })
        local credentials = {}
        lazy_setup(function()
          for i = 1, 3 do
            credentials[i] = admin_api.oauth2_credentials:insert {
              name          = "app" .. i,
              redirect_uris = { helpers.mock_upstream_ssl_url },
              consumer      = { id = consumer.id },
            }
          end
        end)
        lazy_teardown(function()
          for _, credential in ipairs(credentials) do
            admin_api.oauth2_credentials:remove(credential)
          end
        end)
        it("retrieves the first page", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/get_test/oauth2"
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
      local consumer
      local service

      lazy_setup(function()
        service = admin_api.services:insert({ host = "oauth2_token.com" })
        consumer = admin_api.consumers:insert({ username = "bob" })
      end)

      lazy_teardown(function()
        admin_api.consumers:remove(consumer)
        admin_api.services:remove(service)
      end)

      before_each(function()
        credential = admin_api.oauth2_credentials:insert {
          name          = "test app",
          redirect_uris = { helpers.mock_upstream_ssl_url },
          consumer      = { id = consumer.id },
        }
      end)

      after_each(function()
        admin_api.oauth2_credentials:remove(credential)
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
          local alice = admin_api.consumers:insert {
            username = "alice"
          }
          finally(function()
            admin_api.consumers:remove(alice)
          end)

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
            assert.same({ redirect_uris = { "cannot parse 'not-valid'" } }, json.fields)
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

    describe("/oauth2", function()
      describe("POST", function()
        local consumer
        local service

        lazy_setup(function()
          service = admin_api.services:insert({ host = "oauth2_token.com" })
          consumer = admin_api.consumers:insert({ username = "bob" })
        end)

        lazy_teardown(function()
          admin_api.consumers:remove(consumer)
          admin_api.services:remove(service)
        end)

        it("does not create oauth2 credential when missing consumer", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/oauth2",
            body = {
              name = "test",
              redirect_uris =  { "http://localhost/" },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same("schema violation (consumer: required field missing)", json.message)
        end)

        it("creates oauth2 credential", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/oauth2",
            body = {
              name = "test",
              redirect_uris = { "http://localhost/" },
              consumer = {
                id = consumer.id
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("test", json.name)
        end)
      end)
    end)

    describe("/oauth2/:client_id_or_id", function()
      describe("PUT", function()
        local consumer
        local service

        lazy_setup(function()
          service = admin_api.services:insert({ host = "oauth2_token.com" })
          consumer = admin_api.consumers:insert({ username = "bob" })
        end)

        lazy_teardown(function()
          admin_api.consumers:remove(consumer)
          admin_api.services:remove(service)
        end)

        it("does not create oauth2 credential when missing consumer", function()
          local res = assert(admin_client:send {
            method = "PUT",
            path = "/oauth2/client-1",
            body = {
              name = "test",
              redirect_uris =  { "http://localhost/" },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same("schema violation (consumer: required field missing)", json.message)
        end)

        it("creates oauth2 credential", function()
          local res = assert(admin_client:send {
            method = "PUT",
            path = "/oauth2/client-1",
            body    = {
              name = "test",
              redirect_uris =  { "http://localhost/" },
              consumer = {
                id = consumer.id
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("client-1", json.client_id)
          assert.equal("test", json.name)
        end)
      end)
    end)

    describe("/oauth2_tokens/", function()
      describe("POST", function()
        local oauth2_credential
        local consumer
        local service

        lazy_setup(function()
          service = admin_api.services:insert({ host = "oauth2_token.com" })
          consumer = admin_api.consumers:insert({ username = "bob" })
          oauth2_credential = admin_api.oauth2_credentials:insert {
            name          = "Test APP",
            redirect_uris = { helpers.mock_upstream_ssl_url },
            consumer      = { id = consumer.id },
          }
        end)

        lazy_teardown(function()
          admin_api.consumers:remove(consumer)
          admin_api.services:remove(service)
        end)

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
            assert.same({
              expires_in = "required field missing",
              credential = 'required field missing',
            }, json.fields)
          end)
        end)
      end)

      describe("GET", function()
        local oauth2_credential
        local consumer
        local service

        lazy_setup(function()
          service = admin_api.services:insert({ host = "oauth2_token.com" })
          consumer = admin_api.consumers:insert({ username = "bob" })
          oauth2_credential = admin_api.oauth2_credentials:insert {
            name          = "Test APP",
            redirect_uris = { helpers.mock_upstream_ssl_url },
            consumer      = { id = consumer.id },
          }
        end)

        lazy_teardown(function()
          admin_api.consumers:remove(consumer)
          admin_api.services:remove(service)
        end)

        it("retrieves the first page", function()
          for i = 1, 3 do
            admin_api.oauth2_tokens:insert {
              credential = { id = oauth2_credential.id },
              service    = { id = service.id },
              expires_in = 10
            }
          end

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
        local oauth2_credential
        local consumer
        local service

        lazy_setup(function()
          service = admin_api.services:insert({ host = "oauth2_token.com" })
          consumer = admin_api.consumers:insert({ username = "bob" })
          oauth2_credential = admin_api.oauth2_credentials:insert {
            name          = "Test APP",
            redirect_uris = { helpers.mock_upstream_ssl_url },
            consumer      = { id = consumer.id },
          }
        end)

        lazy_teardown(function()
          admin_api.consumers:remove(consumer)
          admin_api.services:remove(service)
        end)

        local token
        before_each(function()
          token = db.oauth2_tokens:insert {
            credential = { id = oauth2_credential.id },
            service    = { id = service.id },
            expires_in = 10
          }
        end)
        after_each(function()
          admin_api.oauth2_tokens:remove(token)
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
              assert.same({
                expires_in = "required field missing",
                credential = 'required field missing',
              }, json.fields)
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
