-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local escape = require("socket.url").escape
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

local match = string.match


local most_common_affected_tables = {
  "files",
  "legacy_files",
  "rbac_users",
  "rbac_user_roles",
  "rbac_roles",
  "rbac_role_entities",
  "rbac_role_endpoints",
  "developers",
  "consumers",
  "basicauth_credentials",
}

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_multipart = fn("multipart/form-data")
  local test_json = fn("application/json")

  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
  it(title .. " with application/json", test_json)
end


local function configure_portal(db, config)
  config = config or {
    portal = true,
  }

  db.workspaces:update_by_name("default", {
    name = "default",
    config = config,
  })
end


local reset_license_data

for _, strategy in helpers.each_strategy() do
  describe("files API (#" .. strategy .. ")({portal_is_legacy = false}): ", function()
    local db

    local client

    local function client_request(params, retries)
      -- Use a singleton.
      -- reuse client as much as possible
      -- sometimes client closes (broken pipe, timeout?), retry at least once with
      -- a new client
      retries = retries or 0
      client = client or assert(helpers.admin_client())
      local res, err = client:send(params)
      if err and retries < 1 then
        client = nil
        return client_request(params, retries + 1)
      end

      assert(res)

      res.body = res:read_body()

      return res
    end


    lazy_setup(function()

      reset_license_data = clear_license_env()

      _, db, _ = helpers.get_db_utils(strategy, most_common_affected_tables)
      assert(helpers.start_kong({
        database = strategy,
        license_path = "spec-ee/fixtures/mock_license.json",
        portal = true,
        portal_and_vitals_key = get_portal_and_vitals_key(),
        portal_is_legacy = false,
      }))

      kong.configuration = {
        portal_is_legacy = false,
      }

      configure_portal(db)
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
      if client then
        client:close()
      end
      reset_license_data()
    end)

    describe('files', function()
      describe("GET", function ()
        lazy_setup(function()
          for i = 1, 100 do
            local content_contents = "--- title: " .. i .. " ---"
            local html_contents = "<h1>" .. i .. "</h1>"
            if math.fmod(i, 2) == 0 then
              assert(db.files:insert {
                path = "content/file-" .. i .. ".txt",
                contents = content_contents
              })
            else
              assert(db.files:insert {
                path = "themes/default/layout/file-" .. i .. ".html",
                contents = html_contents
              })
            end
          end
        end)

        it("retrieves the first page", function()
          local res = client_request({
            methd = "GET",
            path = "/files"
          })
          assert.equal(200, res.status)

          local json = cjson.decode(res.body)
          assert.equal(100, #json.data)
        end)

        it("paginates correctly", function()
          local res = client_request({
            methd = "GET",
            path = "/files?size=50"
          })
          assert.equal(200, res.status)

          local json = cjson.decode(res.body)
          assert.equal(50, #json.data)

          local next = json.next
          local res = client_request({
            methd = "GET",
            path = next
          })
          assert.equal(200, res.status)

          local json = cjson.decode(res.body)
          assert.equal(50, #json.data)
          assert.equal(ngx.null, json.next)
        end)

        it("filters for content files", function()
          local res = client_request({
            methd = "GET",
            path = "/files?type=content&size=25",
          })

          assert.equal(200, res.status)

          local json = cjson.decode(res.body)
          assert.equal(25, #json.data)

          for i, file in ipairs(json.data) do
            assert.equal("content", match(file.path, "^(%w+)/"))
          end

          local next = json.next

          local res = client_request({
            methd = "GET",
            path = next,
          })

          assert.equal(200, res.status)

          local json = cjson.decode(res.body)
          assert.equal(25, #json.data)

          for i, file in ipairs(json.data) do
            assert.equal("content", match(file.path, "^(%w+)/"))
          end

          assert.equal(ngx.null, json.next)
        end)
      end)

      it("returns 405 on invalid method", function()
        local methods = {"DELETE", "PATCH"}
        for i = 1, #methods do
          local res = client_request({
            method = methods[i],
            path = "/files",
            body = {},
            headers = {["Content-Type"] = "application/json"}
          })
          assert.equal(405, res.status)

          local json = cjson.decode(res.body)
          assert.same({ message = "Method not allowed" }, json)
        end
      end)

      describe("POST", function()

        -- XXX: Until these tests are reworded, we need to truncate to
        -- avoid the unique constraint on it_content_types
        before_each(function()
          db:truncate("files")
          db:truncate("rbac_roles")
          db:truncate("rbac_role_endpoints")
        end)

        it_content_types("creates a page", function(content_type)
          return function()
            local contents = [[
---
  title: Hello World
---
]]
            local res = client_request({
              method = "POST",
              path = "/files",
              body = {
                path = "content/test.txt",
                contents = contents
              },
              headers = {["Content-Type"] = content_type}
            })

            local json = cjson.decode(res.body)

            assert.equal("content/test.txt", json.path)
            assert.equal(contents, json.contents)
            assert.is_number(json.created_at)
            assert.is_string(json.id)
          end
        end)

        it_content_types("generates a checksum", function(content_type)
          return function()
            local contents = [[
---
  title: Hello World
---
]]

            local res = client_request({
              method = "POST",
              path = "/files",
              body = {
                path = "content/test.txt",
                contents = contents,
              },
              headers = {["Content-Type"] = content_type}
            })

            assert.equal(201, res.status)

            local json = cjson.decode(res.body)
            assert.equal("content/test.txt", json.path)
            assert.equal(contents, json.contents)
            assert.equal("bd10ca54df3295d72bb491f59c767190bdb0b248ae5d7db74512f62263923736", json.checksum)
            assert.is_number(json.created_at)
            assert.is_string(json.id)
          end
        end)

        it_content_types("takes a user given checksum", function(content_type)
          return function()
            local contents = [[
---
  title: Hello World
---
]]

            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                path = "content/test.txt",
                contents = contents,
                checksum = "123"
              },
              headers = {["Content-Type"] = content_type}
            })

            assert.equal(201, res.status)

            local json = cjson.decode(res.body)
            assert.equal("content/test.txt", json.path)
            assert.equal(contents, json.contents)
            assert.equal("123", json.checksum)
            assert.is_number(json.created_at)
            assert.is_string(json.id)
          end
        end)

        it_content_types("adds permissions using the `content.readable_by`", function(content_type)
          return function()
            local role_res = client_request({
              method = "POST",
              path = "/developers/roles",
              body = { name = "red" },
              headers = {["Content-Type"] = content_type}
            })
            assert.equal(201, role_res.status)

            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                path = "content/test.txt",
                contents = [[
                  ---
                  readable_by: ["red"]
                  ---
                ]],
                checksum = "123"
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.equal(201, res.status)

            local permissions_res = client_request({
              method = "GET",
              path = "/developers/roles/red",
              headers = {["Content-Type"] = content_type}
            })
            assert.equal(200, permissions_res.status)
            local json = cjson.decode(permissions_res.body)
            assert.same({
              default = {
                ["/default/content/test.txt"] = {
                  actions = {
                    read = {
                      negative = false
                    },
                  },
                }
              }
            }, json.permissions)
          end
        end)

        describe("errors", function()
          it_content_types("handles invalid input", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/default/files",
                body = {},
                headers = {["Content-Type"] = content_type}
              })

              assert.equal(400, res.status)
              assert.same({
                code = 2,
                fields = {
                  contents = "required field missing",
                  path = "required field missing",
                },
                message = "2 schema violations (contents: required field missing; path: required field missing)",
                name = "schema violation",
              }, cjson.decode(res.body))
            end
          end)

          it_content_types("returns 409 on conflicting file", function(content_type)
            return function()
              client_request({
                method = "POST",
                path = "/default/files",
                body = {
                  path = "stub.txt",
                  contents = [[
                    ---
                    hello: world
                    ---
                  ]],
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local res = client_request({
                method = "POST",
                path = "/default/files",
                body = {
                  path = "stub.txt",
                  contents = [[
                    ---
                    hello: world
                    ---
                  ]],
                },
                headers = {["Content-Type"] = content_type}
              })

              assert.equals(res.status, 409)
              assert.same({
                code = 5,
                fields = {
                  path = "stub.txt",
                },
                message = [[UNIQUE violation detected on '{path="stub.txt"}']],
                name = "unique constraint violation",
              }, cjson.decode(res.body))
            end
          end)

          it([[returns 400 if the contents contains characters like {*},
            this is fix a security issue specifically 'Server Side Template Injection' #portal]]
            , function()

            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                contents = [[
                  name: Kong Portal
                  app_version: 2fc6a56
                  theme:
                    name: base
                  # main menu
                  menu:
                    - title: Catelog
                      url: documentation
                      needs_auth: false
                  ]],
                path = "portal.conf.yaml",
              },
              headers = { ["Content-Type"] = "application/json" }
            })
            assert.equals(201, res.status)

            local dog_file = cjson.decode(res.body)

            res = client_request({
              method = "PATCH",
              path = "/files/" .. dog_file.id,
              body = {
                path = "portal.conf.yaml",
                contents = [[
                  name: Kong Portal
                  app_version: 2fc6a56
                  theme:
                    name: base
                  # main menu
                  menu:
                    - title: {*}
                      url: documentation
                      needs_auth: false
                  ]],
              },
              headers = { ["Content-Type"] = "application/json" }
            })
            assert.equals(400, res.status)
            local json = cjson.decode(res.body)
            assert.same({
              code = 2,
              fields = {
                ["@entity"] = {
                  [1] = "contents: cannot parse, files with 'spec/' prefix or file is portal.conf" ..
                      " and ending in '.yaml' or '.yml' must be valid yaml,7:30: did not find expected alphabetic or numeric character",
                },
              },
              message = "schema violation (contents: cannot parse, files with 'spec/' prefix" ..
                " or file is portal.conf and ending in '.yaml' or '.yml' must be valid yaml,7:30: did not find" ..
                  " expected alphabetic or numeric character)",
              name = "schema violation"
            }, json)
          end)

          it("returns 415 on invalid content-type", function()
            local res = client_request({
              method = "POST",
              path = "/files",
              body = '{}',
              headers = {["Content-Type"] = "invalid"}
            })
            assert.equals(415, res.status)
          end)

          it("returns 415 on missing content-type with body", function()
            local res = client_request({
              method = "POST",
              path = "/files",
              body = "invalid"
            })
            assert.equals(415, res.status)
          end)

          it("returns 400 on missing body with application/json", function()
            local res = client_request({
              method = "POST",
              path = "/files",
              headers = {["Content-Type"] = "application/json"}
            })

            assert.equals(400, res.status)
            local json = cjson.decode(res.body)
            assert.same({ message = "Cannot parse JSON body" }, json)
          end)

          it("returns 400 on missing body with multipart/form-data", function()
            local res = client_request({
              method = "POST",
              path = "/files",
              headers = {["Content-Type"] = "multipart/form-data"}
            })
            assert.equals(400, res.status)

            local json = cjson.decode(res.body)
            assert.same({
              code = 2,
              fields = {
                contents = "required field missing",
                path = "required field missing",
              },
              message = "2 schema violations (contents: required field missing; path: required field missing)",
              name = "schema violation"
            }, json)
          end)

          it("returns 400 on missing body with multipart/x-www-form-urlencoded", function()
            local res = client_request({
              method = "POST",
              path = "/files",
              headers = {["Content-Type"] = "application/x-www-form-urlencoded"}
            })
            assert.equals(400, res.status)

            local json = cjson.decode(res.body)
            assert.same({
              code = 2,
              fields = {
                contents = "required field missing",
                path = "required field missing",
              },
              message = "2 schema violations (contents: required field missing; path: required field missing)",
              name = "schema violation"
            }, json)
          end)

          it("returns 400 on missing body with no content-type header", function()
            local res = client_request({
              method = "POST",
              path = "/files",
            })
            assert.equals(400, res.status)

            local json = cjson.decode(res.body)
            assert.same({
              code = 2,
              fields = {
                contents = "required field missing",
                path = "required field missing",
              },
              message = "2 schema violations (contents: required field missing; path: required field missing)",
              name = "schema violation",
            }, json)
          end)

          it_content_types("return 400 if path is begins with a slash", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/files",
                body = {
                  path = "/content/slash.md",
                  contents = [[
                    ---
                    key: value
                    ---
                  ]],
                },
                headers = {["Content-Type"] = content_type }
              })
              assert.equals(400, res.status)
              local json = cjson.decode(res.body)
              assert.same({
                code = 2,
                fields = {
                  path = "path must not begin with a slash '/'"
                },
                message = "schema violation (path: path must not begin with a slash '/')",
                name = "schema violation"
              }, json)
            end
          end)

          it_content_types("return 400 if path is missing extention", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/files",
                body = {
                  path = "content/no_ext",
                  contents = [[
                    ---
                    key: value
                    ---
                  ]],
                },
                headers = {["Content-Type"] = content_type }
              })
              assert.equals(400, res.status)
              local json = cjson.decode(res.body)
              assert.same({
                code = 2,
                fields = {
                  path = "path must end with a file extension"
                },
                message = "schema violation (path: path must end with a file extension)",
                name = "schema violation"
              }, json)
            end
          end)

          it_content_types("return 400 if content file extension is invalid", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/files",
                body = {
                  path = "content/file.jpg",
                  contents = [[
                    ---
                    key: value
                    ---
                  ]],
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equals(400, res.status)
              local json = cjson.decode(res.body)
              assert.same({
                code = 2,
                fields = {
                  path = "invalid content extension, must be one of:txt, md, html, json, yaml, yml"
                },
                message = "schema violation (path: invalid content extension, must be one of:txt, md, html, json, yaml, yml)",
                name = "schema violation"
              }, json)
            end
          end)

          it_content_types("return 400 if layout file extension is invalid", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/files",
                body = {
                  path = "themes/theme/layouts/file.jpg",
                  contents = [[
                    ---
                    key: value
                    ---
                  ]],
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equals(400, res.status)
              local json = cjson.decode(res.body)
              assert.same({
                code = 2,
                fields = {
                  path = "layouts and partials must end with extension '.html'"
                },
                message = "schema violation (path: layouts and partials must end with extension '.html')",
                name = "schema violation"
              }, json)
            end
          end)

          it_content_types("return 400 if partial file extension is invalid", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/files",
                body = {
                  path = "themes/theme/partials/file.jpg",
                  contents = [[
                    ---
                    key: value
                    ---
                  ]],
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equals(400, res.status)
              local json = cjson.decode(res.body)
              assert.same({
                code = 2,
                fields = {
                  path = "layouts and partials must end with extension '.html'"
                },
                message = "schema violation (path: layouts and partials must end with extension '.html')",
                name = "schema violation"
              }, json)
            end
          end)

          it_content_types("return 400 if spec file extension is invalid", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/files",
                body = {
                  path = "specs/mySpec.bad",
                  contents = [[
                    title: "bad"
                  ]],
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equals(400, res.status)
              local json = cjson.decode(res.body)
              assert.same({
                code = 2,
                fields = {
                  path = "invalid spec extension, must be one of:json, yaml, yml"
                },
                message = "schema violation (path: invalid spec extension, must be one of:json, yaml, yml)",
                name = "schema violation"
              }, json)
            end
          end)

          it_content_types("returns 400 on inexisting roles", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/files",
                body = {
                  path = "content/test.txt",
                  contents = [[
                    ---
                    readable_by: ["red"]
                    ---
                  ]],
                  checksum = "123"
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equals(400, res.status)
              local json = cjson.decode(res.body)
              assert.same({ "could not find role: red" }, json.fields["@entity"])
            end
          end)

          it_content_types("returns 400 if content file contents is not stringified yaml", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/files",
                body = {
                  path = "content/test.txt",
                  contents = "---not yaml or json-",
                },
                headers = {["Content-Type"] = content_type}
              })

              assert.equals(400, res.status)

              local json = cjson.decode(res.body)
              assert.same({
                code = 2,
                fields = {
                  ["@entity"] = {
                    [1] = "contents: cannot parse, files with 'content/' prefix must have valid headmatter/body syntax"
                  },
                },
                message = "schema violation (contents: cannot parse, files with 'content/' prefix must have valid headmatter/body syntax)",
                name = "schema violation",
              }, json)
            end
          end)

          it_content_types("returns 400 if yaml spec file contents is not yaml", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/files",
                body = {
                  path = "specs/bad.yaml",
                  contents = [[
                    bad: '*"
                  ]]
                },
                headers = {["Content-Type"] = content_type}
              })

              assert.equals(400, res.status)

              local json = cjson.decode(res.body)
              assert.same({
                code = 2,
                fields = {
                  ["@entity"] = {
                    [1] = "contents: cannot parse, files with 'spec/' prefix or file is portal.conf and" ..
                    " ending in '.yaml' or '.yml' must be valid yaml,1:21: found unexpected end of stream"
                  },
                },
                message = "schema violation (contents: cannot parse, files with 'spec/' prefix or file is portal.conf and" ..
                " ending in '.yaml' or '.yml' must be valid yaml,1:21: found unexpected end of stream)",
                name = "schema violation",
              }, json)
            end
          end)

          it_content_types("returns 400 if json spec file contents is not json", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/files",
                body = {
                  path = "specs/badjson.json",
                  contents = '{bad: "json}'
                },
                headers = {["Content-Type"] = content_type}
              })

              assert.equals(400, res.status)

              local json = cjson.decode(res.body)
              assert.same({
                code = 2,
                fields = {
                  ["@entity"] = {
                    [1] = "contents: cannot parse, files with 'spec/' prefix and ending in '.json' must be valid json"
                  },
                },
                message = "schema violation (contents: cannot parse, files with 'spec/' prefix and ending in '.json' must be valid json)",
                name = "schema violation",
              }, json)
            end
          end)

          it_content_types("returns 400 if readable_by is invalid type", function(content_type)
            return function()
              local red_res = client_request({
                method = "POST",
                path = "/developers/roles",
                body = { name = "red" },
                headers = {["Content-Type"] = content_type}
              })
              assert.equal(201, red_res.status)

              local blue_res = client_request({
                method = "POST",
                path = "/developers/roles",
                body = { name = "blue" },
                headers = {["Content-Type"] = content_type}
              })
              assert.equal(201, blue_res.status)

              local res = client_request({
                method = "POST",
                path = "/default/files",
                body = {
                  contents = [[
                    ---
                    readable_by:
                      - red:
                        - blue
                    ---
                  ]],
                  path = "content/test.txt",
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equal(400,res.status)
              local json = cjson.decode(res.body)
              assert.same({
                code = 2,
                fields = {
                  ["@entity"] = {
                    [1] = "readable_by must be a string role or array of string roles"
                  },
                },
                message = "schema violation (readable_by must be a string role or array of string roles)",
                name = "schema violation",
              }, json)
            end
          end)
        end)
      end)

      describe("/files/{file_splat}", function()
        local dog_file, dog_file_slash

        before_each(function()
          db:truncate("files")
          db:truncate("rbac_roles")
          db:truncate("rbac_role_endpoints")
        end)

        describe("GET", function()
          it("retrieves by id", function()
            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                path = "dog.gif",
                contents = "cat"
              },
              headers = {["Content-Type"] = "application/json"}
            })
            dog_file = cjson.decode(res.body)

            local res = client_request({
              method = "GET",
              path = "/files/" .. dog_file.id
            })

            assert.equals(200, res.status)
            local json = cjson.decode(res.body)
            assert.same(dog_file, json)
          end)

          it("retrieves by name", function()
            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                path = "dog.gif",
                contents = "cat"
              },
              headers = {["Content-Type"] = "application/json"}
            })
            dog_file = cjson.decode(res.body)

            local res = client_request({
              method = "GET",
              path = "/files/" .. dog_file.path
            })

            assert.equals(200, res.status)
            local json = cjson.decode(res.body)
            assert.same(dog_file, json)
          end)

          it("retrieves by urlencoded name", function()
            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                path = "dog.gif",
                contents = "cat"
              },
              headers = {["Content-Type"] = "application/json"}
            })
            dog_file = cjson.decode(res.body)

            local res = client_request({
              method = "GET",
              path = "/files/" .. escape(dog_file.path),
            })

            assert.equals(200, res.status)
            local json = cjson.decode(res.body)
            assert.same(dog_file, json)
          end)

          it("returns 404 if not found", function()
            local res = client_request({
              method = "GET",
              path = "/files/_inexistent_.txt"
            })
            assert.res_status(404, res)
          end)

          it("returns 404 if not found (slash in name)", function()
            local res = client_request({
              method = "GET",
              path = "/files/stub/something.jpg"
            })
            assert.res_status(404, res)
          end)

          it("retrieves by name (slash in name)", function()
            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                path = "dog/slash.gif",
                contents = "cat"
              },
              headers = {["Content-Type"] = "application/json"}
            })

            dog_file_slash = cjson.decode(res.body)

            local res = client_request({
              method = "GET",
              path = "/files/" .. dog_file_slash.path
            })

            assert.equals(200, res.status)
            local json = cjson.decode(res.body)
            assert.same(dog_file_slash, json)
          end)

          it("retrieves by urlencoded name (slash in name)", function()
            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                path = "dog/slash.gif",
                contents = "cat"
              },
              headers = {["Content-Type"] = "application/json"}
            })

            dog_file_slash = cjson.decode(res.body)

            local res = client_request({
              method = "GET",
              path = "/files/" .. escape(dog_file_slash.path),
            })

            assert.equals(200, res.status)
            local json = cjson.decode(res.body)
            assert.same(dog_file_slash, json)
          end)
        end)

        describe("PATCH", function()
          it_content_types("updates by id", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/default/files",
                body = {
                  path = "dog.gif",
                  contents = "cat"
                },
                headers = {["Content-Type"] = "application/json"}
              })
              assert.equals(201, res.status)
              dog_file = cjson.decode(res.body)

              res = client_request({
                method = "PATCH",
                path = "/default/files/" .. dog_file.id,
                body = {
                  contents = "bar",
                  path = "changed_path.png",
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equals(200, res.status)

              local json = cjson.decode(res.body)
              assert.equal("bar", json.contents)
              assert.equal("changed_path.png", json.path)
              assert.equal(dog_file.id, json.id)

              dog_file = assert(db.files:select {
                id = dog_file.id,
              })
              assert.same(json, dog_file)

              local res = client_request({
                method = "GET",
                path = "/files/" .. dog_file.path
              })

              assert.equals(200, res.status)
              local json = cjson.decode(res.body)
              assert.same(dog_file, json)
            end
          end)

          it_content_types("updates by path", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/default/files",
                body = {
                  path = "dog.gif",
                  contents = "cat"
                },
                headers = {["Content-Type"] = "application/json"}
              })
              assert.equals(201, res.status)
              dog_file = cjson.decode(res.body)

              local res = client_request({
                method = "PATCH",
                path = "/files/" .. dog_file.path,
                body = {
                  contents = "bar",
                  path = "changed_path.png",
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equals(200, res.status)

              local json = cjson.decode(res.body)
              assert.equal("bar", json.contents)
              assert.equal("changed_path.png", json.path)
              assert.equal(dog_file.id, json.id)

              dog_file = assert(db.files:select {
                id = dog_file.id,
              })

              assert.same(json, dog_file)

              local res = client_request({
                method = "GET",
                path = "/files/" .. dog_file.path
              })

              assert.equals(200, res.status)
              local json = cjson.decode(res.body)
              assert.same(dog_file, json)
            end
          end)

          it_content_types("updates by path (slash in path)", function(content_type)
            return function()
              local res = client_request({
                method = "POST",
                path = "/default/files",
                body = {
                  contents = "foo",
                  path = "changed_path/with_slash.gif",
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equals(201, res.status)
              dog_file = cjson.decode(res.body)

              local res = client_request({
                method = "PATCH",
                path = "/default/files/" .. dog_file.path,
                body = {
                  contents = "bar",
                  path = "changed_path/with_slash.gif",
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equals(200, res.status)

              local json = cjson.decode(res.body)
              assert.equal("bar", json.contents)
              assert.equal("changed_path/with_slash.gif", json.path)
              assert.equal(dog_file.id, json.id)

              dog_file = assert(db.files:select {
                id = dog_file.id,
              })

              assert.same(json, dog_file)

              local res = client_request({
                method = "GET",
                path = "/files/" .. dog_file.path
              })

              assert.equals(200, res.status)
              local json = cjson.decode(res.body)
              assert.same(dog_file, json)
            end
          end)

          it_content_types("updates permissions using the `readable_by` content", function(content_type)
            return function()
              local red_res = client_request({
                method = "POST",
                path = "/developers/roles",
                body = { name = "red" },
                headers = {["Content-Type"] = content_type}
              })
              assert.equal(201, red_res.status)

              local blue_res = client_request({
                method = "POST",
                path = "/developers/roles",
                body = { name = "blue" },
                headers = {["Content-Type"] = content_type}
              })
              assert.equal(201, blue_res.status)

              local res = client_request({
                method = "POST",
                path = "/default/files",
                body = {
                  contents = [[
                    ---
                    readable_by: ["red"]
                    ---
                  ]],
                  path = "content/test.txt",
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equal(201,res.status)
              local file = cjson.decode(res.body)

              local res = client_request({
                method = "PATCH",
                path = "/default/files/" .. file.id,
                body = {
                  contents = [[
                    ---
                    readable_by: ["blue"]
                    ---
                  ]],
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.equal(200,res.status)

              local res = client_request({
                method = "GET",
                path = "/developers/roles/red",
                headers = {["Content-Type"] = content_type}
              })
              assert.equal(200, res.status)
              local json = cjson.decode(res.body)
              assert.same({}, json.permissions)

              local res = client_request({
                method = "GET",
                path = "/developers/roles/blue",
                headers = {["Content-Type"] = content_type}
              })
              assert.equal(200, res.status)
              local json = cjson.decode(res.body)
              assert.same({
                default = {
                  ["/default/content/test.txt"] = {
                    actions = {
                      read = {
                        negative = false
                      },
                    },
                  }
                }
              }, json.permissions)
            end
          end)

          describe("errors", function()
            it_content_types("returns 404 if not found", function(content_type)
              return function()
                local res = client_request({
                  method = "PATCH",
                  path = "/files/_inexistent_.txt",
                  body = {
                    path = "alice.md",
                    contents = [[
                      ---
                      title: "this contents must be here to pass entity check"
                      ---
                    ]]
                  },
                  headers = {["Content-Type"] = content_type}
                })
                assert.equals(404, res.status)
              end
            end)

            it_content_types("returns 404 if not found (slash in name)", function(content_type)
              return function()
                local res = client_request({
                  method = "PATCH",
                  path = "/files/stub/_inexistent_.txt",
                  body = {
                    path = "alice.md",
                    contents = [[
                      ---
                      title: "this contents must be here to pass entity check"
                      ---
                    ]]
                  },
                  headers = {["Content-Type"] = content_type}
                })
                assert.equals(404, res.status)
              end
            end)

            it("returns 415 on invalid content-type", function()
              local res = client_request({
                method = "POST",
                path = "/default/files",
                body = {
                  contents = "foo",
                  path = "changed_path/with_slash.txt",
                },
                headers = {["Content-Type"] = "application/json"}
              })
              assert.equals(201, res.status)
              dog_file = cjson.decode(res.body)

              local res = client_request({
                method = "PATCH",
                path = "/files/" .. dog_file.id,
                body = '{"hello": "world"}',
                headers = {["Content-Type"] = "invalid"}
              })
              assert.equals(415, res.status)
            end)

            it("returns 415 on missing content-type with body ", function()
              local res = client_request({
                method = "POST",
                path = "/default/files",
                body = {
                  contents = "foo",
                  path = "changed_path/with_slash.txt",
                },
                headers = {["Content-Type"] = "application/json"}
              })
              assert.equals(201, res.status)
              dog_file = cjson.decode(res.body)

              local res = client_request({
                method = "PATCH",
                path = "/files/" .. dog_file.id,
                body = "invalid"
              })
              assert.equals(415, res.status)
            end)

            it("returns 400 on missing body with application/json", function()
              local res = client_request({
                method = "POST",
                path = "/default/files",
                body = {
                  contents = "foo",
                  path = "changed_path/with_slash.md",
                },
                headers = {["Content-Type"] = "application/json"}
              })
              assert.equals(201, res.status)
              dog_file = cjson.decode(res.body)

              local res = client_request({
                method = "PATCH",
                path = "/files/" .. dog_file.id,
                headers = {["Content-Type"] = "application/json"}
              })

              local json = cjson.decode(res.body)
              assert.same({ message = "Cannot parse JSON body" }, json)
            end)
          end)
        end)

        describe("DELETE", function()
          it("deletes by id", function()
            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                contents = "foo",
                path = "changed_path/with_slash.txt",
              },
              headers = {["Content-Type"] = "application/json"}
            })
            assert.equals(201, res.status)
            dog_file = cjson.decode(res.body)

            local res = client_request({
              method = "DELETE",
              path = "/files/" .. dog_file.id
            })
            assert.equals(204, res.status)

            local res = client_request({
              method = "GET",
              path = "/default/files/" .. dog_file.id,
            })

            assert.equals(404, res.status)
          end)

          it("deletes by name", function()
            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                contents = "foo",
                path = "changed_path/with_slash.txt",
              },
              headers = {["Content-Type"] = "application/json"}
            })
            assert.equals(201, res.status)
            dog_file = cjson.decode(res.body)

            local res = client_request({
              method = "DELETE",
              path = "/files/" .. dog_file.path
            })

            assert.equals(204, res.status)

            local res = client_request({
              method = "GET",
              path = "/default/files/" .. dog_file.id,
            })

            assert.equals(404, res.status)
          end)

          it("deletes by name (slash in name)", function()
            local res = client_request({
              method = "DELETE",
              path = "/files/" .. dog_file.path
            })
            assert.equals(204, res.status)

            local res = client_request({
              method = "GET",
              path = "/default/files/" .. dog_file.id,
            })

            assert.equals(404, res.status)
          end)

          it("deletes permissions", function()
            local role_res = client_request({
              method = "POST",
              path = "/developers/roles",
              body = { name = "red" },
              headers = { ["Content-Type"] = "application/json" }
            })
            assert.equal(201, role_res.status)

            local res = client_request({
              method = "POST",
              path = "/default/files",
              body = {
                path = "content/test.txt",
                contents = [[
                  ---
                  readable_by:
                    - red
                  ---
                ]],
                checksum = "123"
              },
              headers = { ["Content-Type"] = "application/json" }
            })
            assert.equal(201, res.status)
            local file = cjson.decode(res.body)

            local res = client_request({
              method = "DELETE",
              path = "/default/files/" .. file.id,
              headers = { ["Content-Type"] = "application/json" }
            })
            assert.equal(204, res.status)

            local permissions_res = client_request({
              method = "GET",
              path = "/developers/roles/red",
              headers = { ["Content-Type"] = "application/json" }
            })
            assert.equal(200, permissions_res.status)
            local json = cjson.decode(permissions_res.body)
            assert.same({}, json.permissions)
          end)
        end)
      end)
    end)
  end)

  describe("files API (#" .. strategy .. ")({portal_is_legacy = true}): ", function()
    local db
    local client
    local fileStub
    local fileSlashStub

    lazy_setup(function()
      reset_license_data = clear_license_env()
      _, db, _ = helpers.get_db_utils(strategy, most_common_affected_tables)
      assert(helpers.start_kong({
        database = strategy,
        license_path = "spec-ee/fixtures/mock_license.json",
        portal = true,
        portal_and_vitals_key = get_portal_and_vitals_key(),
        portal_is_legacy = true,
      }))

      kong.configuration = {
        portal_is_legacy = true,
      }

      configure_portal(db)

      client = helpers.admin_client()
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
      if client then
        client:close()
      end
      reset_license_data()
    end)

    describe("/files", function()
      describe("POST", function()
        before_each(function()
          db:truncate("files")
          db:truncate("legacy_files")

          fileStub = assert(db.files:insert {
            name = "stub",
            contents = "1",
            type = "page"
          })

          fileSlashStub = assert(db.files:insert {
            name = "slash/stub",
            contents = "1",
            type = "page"
          })
        end)

        it_content_types("creates a page", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/files",
              body = {
                name = "test",
                contents = '{"hello":"world"}',
                type = "page"
              },
              headers = {["Content-Type"] = content_type}
            })

            local body = assert.res_status(201, res)
            local json = cjson.decode(body)

            assert.equal("test", json.name)
            assert.equal('{"hello":"world"}', json.contents)
            assert.equal("page", json.type)
            assert.is_true(json.auth)
            assert.is_number(json.created_at)
            assert.is_string(json.id)
          end
        end)

        describe("errors", function()
          it_content_types("handles invalid input", function(content_type)
            return function()
              local res = assert(client:send {
                method = "POST",
                path = "/files",
                body = {},
                headers = {["Content-Type"] = content_type}
              })

              local body = assert.res_status(400, res)
              local json = cjson.decode(body)

              assert.same({
                code = 2,
                fields = {
                  contents = "required field missing",
                  name = "required field missing",
                },
                message = "2 schema violations (contents: required field missing; name: required field missing)",
                name = "schema violation",
              }, json)
            end
          end)

          it_content_types("returns 409 on conflicting file", function(content_type)
            return function()
              local res = assert(client:send {
                method = "POST",
                path = "/files",
                body = {
                  name = fileStub.name,
                  contents = '{"hello":"world"}',
                  type = "page"
                },
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.res_status(409, res)
              local json = cjson.decode(body)
              assert.same({
                code = 5,
                fields = {
                  name = "stub",
                },
                message = [[UNIQUE violation detected on '{name="stub"}']],
                name = "unique constraint violation",
              }, json)
            end
          end)

          it_content_types("returns 409 on conflicting file (slash in name)", function(content_type)
            return function()
              local res = assert(client:send {
                method = "POST",
                path = "/files",
                body = {
                  name = fileSlashStub.name,
                  contents = '{"hello":"world"}',
                  type = "page"
                },
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.res_status(409, res)
              local json = cjson.decode(body)
              assert.same({
                code = 5,
                fields = {
                  name = "slash/stub",
                },
                message = [[UNIQUE violation detected on '{name="slash/stub"}']],
                name = "unique constraint violation",
              }, json)
            end
          end)

          it("returns 415 on invalid content-type", function()
            local res = assert(client:send {
              method = "POST",
              path = "/files",
              body = '{}',
              headers = {["Content-Type"] = "invalid"}
            })
            assert.res_status(415, res)
          end)

          it("returns 415 on missing content-type with body", function()
            local res = assert(client:request {
              method = "POST",
              path = "/files",
              body = "invalid"
            })
            assert.res_status(415, res)
          end)

          it("returns 400 on missing body with application/json", function()
            local res = assert(client:request {
              method = "POST",
              path = "/files",
              headers = {["Content-Type"] = "application/json"}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Cannot parse JSON body" }, json)
          end)

          it("returns 400 on missing body with multipart/form-data", function()
            local res = assert(client:request {
              method = "POST",
              path = "/files",
              headers = {["Content-Type"] = "multipart/form-data"}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              code = 2,
              fields = {
                contents = "required field missing",
                name = "required field missing",
              },
              message = "2 schema violations (contents: required field missing; name: required field missing)",
              name = "schema violation"
            }, json)
          end)

          it("returns 400 on missing body with multipart/x-www-form-urlencoded", function()
            local res = assert(client:request {
              method = "POST",
              path = "/files",
              headers = {["Content-Type"] = "application/x-www-form-urlencoded"}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              code = 2,
              fields = {
                contents = "required field missing",
                name = "required field missing",
              },
              message = "2 schema violations (contents: required field missing; name: required field missing)",
              name = "schema violation"
            }, json)
          end)

          it("returns 400 on missing body with no content-type header", function()
            local res = assert(client:request {
              method = "POST",
              path = "/files",
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              code = 2,
              fields = {
                contents = "required field missing",
                name = "required field missing",
              },
              message = "2 schema violations (contents: required field missing; name: required field missing)",
              name = "schema violation",
            }, json)
          end)

          it_content_types("returns 400 on improper type declaration", function(content_type)
            return function()
              local res = assert(client:send {
                method = "POST",
                path = "/files",
                body = {
                  name = "test",
                  contents = '{"hello":"world"}',
                  type = "dog"
                },
                headers = {["Content-Type"] = content_type}
              })

              local body = assert.res_status(400, res)
              local json = cjson.decode(body)
              assert.same({
                code = 2,
                fields = {
                  type = "expected one of: page, partial, spec",
                },
                message = "schema violation (type: expected one of: page, partial, spec)",
                name = "schema violation",
              }, json)
            end
          end)

          it_content_types("returns 400 on improper type declaration (slash in name)", function(content_type)
            return function()
              local res = assert(client:send {
                method = "POST",
                path = "/files",
                body = {
                  name = "slash/test",
                  contents = '{"hello":"world"}',
                  type = "dog"
                },
                headers = {["Content-Type"] = content_type}
              })

              local body = assert.res_status(400, res)
              local json = cjson.decode(body)
              assert.same({
                code = 2,
                fields = {
                  type = "expected one of: page, partial, spec",
                },
                message = "schema violation (type: expected one of: page, partial, spec)",
                name = "schema violation",
              }, json)
            end
          end)
        end)
      end)

      describe("GET", function ()
        lazy_setup(function()
          -- XXX get rid of stubs
          db:truncate("files")
          db:truncate("legacy_files")
          for i = 1, 100 do
            if math.fmod(i, 2) == 0 then
              assert(db.files:insert {
                name = "file-" .. i,
                contents = "i-" .. i,
                type = "page",
                auth = true
              })
            else
              assert(db.files:insert {
                name = "file-" .. i,
                contents = "i-" .. i,
                type = "partial",
                auth = false
              })
            end
          end
        end)

        it("retrieves the first page", function()
          local res = assert(client:send {
            methd = "GET",
            path = "/files"
          })
          res = assert.res_status(200, res)
          local json = cjson.decode(res)
          assert.equal(100, #json.data)
        end)

        it("paginates correctly", function()
          local res = assert(client:send {
            methd = "GET",
            path = "/files?size=50"
          })
          res = assert.res_status(200, res)
          local json = cjson.decode(res)
          assert.equal(50, #json.data)

          local next = json.next
          local res = assert(client:send {
            methd = "GET",
            path = next
          })
          res = assert.res_status(200, res)
          local json = cjson.decode(res)
          assert.equal(50, #json.data)
          assert.equal(ngx.null, json.next)
        end)

        it("can filter", function()
          local res = assert(client:send {
            methd = "GET",
            path = "/files?type=partial"
          })
          res = assert.res_status(200, res)
          local json = cjson.decode(res)
          assert.equal(50, #json.data)

          local res = assert(client:send {
            methd = "GET",
            path = "/files?type=page"
          })
          res = assert.res_status(200, res)
          local json = cjson.decode(res)
          assert.equal(50, #json.data)
        end)

        it("can filter and paginate", function()
          local res = assert(client:send {
            methd = "GET",
            path = "/files?type=partial&size=2"
          })
          res = assert.res_status(200, res)
          local json = cjson.decode(res)
          assert.equal(2, #json.data)
          assert.equal('partial', json.data[1].type)
        end)
      end)

      it("returns 405 on invalid method", function()
        local methods = {"DELETE", "PATCH"}
        for i = 1, #methods do
          local res = assert(client:send {
            method = methods[i],
            path = "/files",
            body = {},
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.response(res).has.status(405)
          local json = cjson.decode(body)

          assert.same({ message = "Method not allowed" }, json)
        end
      end)

      describe("/files/{file_splat}", function()
        before_each(function()
          db:truncate("files")
          db:truncate("legacy_files")

          fileStub = assert(db.files:insert {
            name = "stub",
            contents = "1",
            type = "page"
          })

          fileSlashStub = assert(db.files:insert {
            name = "slash/stub",
            contents = "1",
            type = "page"
          })
        end)
        describe("GET", function()
          it("retrieves by id", function()
            local res = assert(client:send {
              method = "GET",
              path = "/files/" .. fileStub.id
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(fileStub, json)
          end)

          it("retrieves by name", function()
            local res = assert(client:send {
              method = "GET",
              path = "/files/" .. fileStub.name
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(fileStub, json)
          end)

          it("retrieves by urlencoded name", function()
            local res = assert(client:send {
              method = "GET",
              path = "/files/" .. escape(fileStub.name),
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(fileStub, json)
          end)

          it("returns 404 if not found", function()
            local res = assert(client:send {
              method = "GET",
              path = "/files/_inexistent_"
            })
            assert.res_status(404, res)
          end)

          it("returns 404 if not found (slash in name)", function()
            local res = assert(client:send {
              method = "GET",
              path = "/files/stub/something"
            })
            assert.res_status(404, res)
          end)

          it("retrieves by name (slash in name)", function()
            local res = assert(client:send {
              method = "GET",
              path = "/files/" .. fileSlashStub.name
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(fileSlashStub, json)
          end)

          it("retrieves by urlencoded name (slash in name)", function()
            local res = assert(client:send {
              method = "GET",
              path = "/files/" .. escape(fileSlashStub.name),
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(fileSlashStub, json)
          end)
        end)

        describe("PATCH", function()
          it_content_types("updates by id", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/files/" .. fileStub.id,
                body = {
                  contents = "bar",
                  name = "changed_name",
                  auth = false,
                },
                headers = {["Content-Type"] = content_type}
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.equal("bar", json.contents)
              assert.equal("changed_name", json.name)
              assert.equal(false, json.auth)
              assert.equal(fileStub.id, json.id)

              fileStub = assert(db.files:select {
                id = fileStub.id,
              })
              assert.same(json, fileStub)

              local res = assert(client:send {
                method = "GET",
                path = "/files/" .. fileStub.name
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(fileStub, json)
            end
          end)

          it_content_types("updates by name", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/files/" .. fileStub.name,
                body = {
                  contents = "bar",
                  name = "changed_name_again",
                  auth = false,
                },
                headers = {["Content-Type"] = content_type}
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.equal("bar", json.contents)
              assert.equal("changed_name_again", json.name)
              assert.equal(false, json.auth)
              assert.equal(fileStub.id, json.id)

              fileStub = assert(db.files:select {
                id = fileStub.id,
              })

              assert.same(json, fileStub)

              local res = assert(client:send {
                method = "GET",
                path = "/files/" .. fileStub.name
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(fileStub, json)
            end
          end)

          it_content_types("updates by name (slash in name)", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/files/" .. fileSlashStub.name,
                body = {
                  contents = "bar",
                  name = "changed_name/with_slash",
                  auth = true,
                },
                headers = {["Content-Type"] = content_type}
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.equal("bar", json.contents)
              assert.equal("changed_name/with_slash", json.name)
              assert.equal(true, json.auth)
              assert.equal(fileSlashStub.id, json.id)

              fileSlashStub = assert(db.files:select {
                id = fileSlashStub.id,
              })

              assert.same(json, fileSlashStub)


              local res = assert(client:send {
                method = "GET",
                path = "/files/" .. fileSlashStub.name
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(fileSlashStub, json)
            end
          end)
          describe("errors", function()
            it_content_types("returns 404 if not found", function(content_type)
              return function()
                local res = assert(client:send {
                  method = "PATCH",
                  path = "/files/_inexistent_",
                  body = {
                  name = "alice"
                  },
                  headers = {["Content-Type"] = content_type}
                })
                assert.res_status(404, res)
              end
            end)

            it_content_types("returns 404 if not found (slash in name)", function(content_type)
              return function()
                local res = assert(client:send {
                  method = "PATCH",
                  path = "/files/stub/_inexistent_",
                  body = {
                  name = "alice"
                  },
                  headers = {["Content-Type"] = content_type}
                })
                assert.res_status(404, res)
              end
            end)
            it("returns 415 on invalid content-type", function()
              local res = assert(client:request {
                method = "PATCH",
                path = "/files/" .. fileStub.id,
                body = '{"hello": "world"}',
                headers = {["Content-Type"] = "invalid"}
              })
              assert.res_status(415, res)
            end)
            it("returns 415 on missing content-type with body ", function()
              local res = assert(client:request {
                method = "PATCH",
                path = "/files/" .. fileStub.id,
                body = "invalid"
              })
              assert.res_status(415, res)
            end)
            it("returns 400 on missing body with application/json", function()
              local res = assert(client:request {
                method = "PATCH",
                path = "/files/" .. fileStub.id,
                headers = {["Content-Type"] = "application/json"}
              })
              local body = assert.res_status(400, res)
              local json = cjson.decode(body)
              assert.same({ message = "Cannot parse JSON body" }, json)
            end)
          end)
        end)

        describe("DELETE", function()
          it("deletes by id", function()
            local res = assert(client:send {
              method = "DELETE",
              path = "/files/" .. fileStub.id
            })
            local body = assert.res_status(204, res)
            assert.equal("", body)
          end)
          it("deletes by name", function()
            local res = assert(client:send {
              method = "DELETE",
              path = "/files/" .. fileStub.name
            })
            local body = assert.res_status(204, res)
            assert.equal("", body)
          end)

          it("deletes by name (slash in name)", function()
            local res = assert(client:send {
              method = "DELETE",
              path = "/files/" .. fileSlashStub.name
            })
            local body = assert.res_status(204, res)
            assert.equal("", body)
          end)
        end)
      end)
    end)
  end)
end
