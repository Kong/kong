-- This software is copyright Kong Inc. and its licensors.

-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("json body transform #" .. strategy, function()
    local proxy_client, admin_client, route, plugin
    local data = {
      default = {
        route = {
          name = "default_route",
        },
        plugins = {
          { name = "acl", order = 100 },
          { name = "transformer", order = 200 },
          { name = "authenticator", order = 300 },
        },
      },
      kong = {
        route = {
          name = "new_route",
          sevice = "new_service"
        },
      },
    }

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {"request-transformer-advanced"})

      local service = assert(bp.services:insert {
        name = "service-req-trans",
        host = "echo_server",
        protocol = "http",
        port = 10001,
      })

      route = bp.routes:insert({
        service   = service,
        paths = {"/req"},
      })

      plugin = bp.plugins:insert({
        name = "request-transformer-advanced",
        config = {
          remove = {body = {},},
          rename = {body = {},},
          replace = {body = {},},
          add = {body = {},},
          append = {body = {},},
        },
        route = { id = route.id },
      })

      local fixtures = {
        dns_mock = helpers.dns_mock.new(),
        http_mock = {
          echo_server = [[
            server {
                server_name echo_server;
                listen 10001;

                location ~ "/echobody" {
                  content_by_lua_block {
                    ngx.req.read_body()
                    local echo = ngx.req.get_body_data()
                    ngx.status = 200
                    ngx.header["Content-Length"] = #echo + 1
                    ngx.say(echo)
                  }
                }
            }
          ]]
        },
      }

      fixtures.dns_mock:A {
        name = "echo_server",
        address = "127.0.0.1",
      }

      assert(helpers.start_kong({
        database          = strategy,
        plugins           = "request-transformer-advanced",
        nginx_conf        = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function ()
      helpers.stop_kong()
      if admin_client then admin_client:close() end
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    local function execute(config, expected)
      local res = assert(admin_client:send {
        method  = "PUT",
        path    = "/plugins/" .. plugin.id,
        body    = {
          name  = "request-transformer-advanced",
          route = { id = route.id },
          config = config,
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      assert.res_status(200, res)

      assert.eventually(function()
        res = proxy_client:send {
          method = "POST",
          path = "/req/echobody",
          body = data,
          headers = {
            ["Host"] = "echo_server",
            ["Content-Type"] = "application/json",
          },
        }
        local body = assert.res_status(200, res)
        local json_body = cjson.decode(body)
        assert(require("pl.tablex").deepcompare(json_body, expected), "Expected equal json bodies")
      end).with_timeout(3)
          .has_no_error("Expected equal json bodies")
    end

    describe("without index ", function ()
      describe("remove", function ()
        it("present", function ()
          local config = {
            dots_in_keys = false,
            remove = {
              body = {"kong.route.name"},
            },
            rename = {body = {},},
            replace = {body = {},},
            add = {body = {},},
            append = {body = {},},
          }

          local expected = utils.cycle_aware_deep_copy(data)
          expected['kong']['route']['name'] = nil

          execute(config, expected)
        end)

        it("not present", function ()
          local config = {
            dots_in_keys = false,
            remove = {
              body = {"kong.route.unknown"},
            },
            rename = {body = {},},
            replace = {body = {},},
            add = {body = {},},
            append = {body = {},},
          }

          execute(config, data)
        end)
      end)

      describe("rename", function()
        it("present", function ()
          local config = {
            dots_in_keys = false,
            rename = {
              body = {"kong.route.name:kong.route.nickname"},
            },
            remove = {body = {},},
            replace = {body = {}},
            add = {body = {}},
            append = {body = {}},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          local v = expected['kong']['route']['name']
          expected['kong']['route']['name'] = nil
          expected['kong']['route']['nickname'] = v

          execute(config, expected)
        end)

        it("not present", function()
          local config = {
            dots_in_keys = false,
            rename = {
              body = {"kong.route.unknown:kong.route.unknown"},
            },
            remove = {body = {},},
            replace = {body = {}},
            add = {body = {}},
            append = {body = {}},
          }

          execute(config, data)
        end)
      end)

      describe("replace", function()
        it("present", function ()
          local config = {
            dots_in_keys = false,
            replace = {
              body = {"kong.route.name:replace"},
            },
            rename = {body = {},},
            remove = {body = {},},
            add = {body = {},},
            append = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          expected['kong']['route']['name'] = "replace"

          execute(config, expected)
        end)

        it("not present", function()
          local config = {
            dots_in_keys = false,
            replace = {
              body = {"kong.route.unknown:replace"},
            },
            rename = {body = {},},
            remove = {body = {},},
            add = {body = {},},
            append = {body = {},},
          }

          execute(config, data)
        end)
      end)

      describe("add", function()
        it("present", function()
          local config = {
            dots_in_keys = false,
            add = {
              body = {"kong.route.name:wont_add"},
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            append = {body = {},},
          }

          execute(config, data)
        end)

        it("not present", function ()
          local config = {
            dots_in_keys = false,
            add = {
              body = {"kong.route.plugins:add"},
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            append = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          expected['kong']['route']['plugins'] = "add"

          execute(config, expected)
        end)
      end)

      describe("append", function ()
        it("not present", function ()
          local config = {
            dots_in_keys = false,
            append = {
              body = { "default.service:append" },
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            add = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          expected['default']['service'] = { "append" }

          execute(config, expected)
        end)

        it("present", function ()
          local config = {
            dots_in_keys = false,
            append = {
              body = {"default.plugins:append" },
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            add = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          table.insert(expected['default']['plugins'], "append")

          execute(config, expected)
        end)
      end)

      describe("allow", function()
        it("allow.body does not contain nested syntax", function()
          local config = {
            dots_in_keys = false,
            allow = {
              body = { "kong" },
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            add = {body = {},},
          }
          local expected = { kong = data.kong }

          execute(config, expected)
        end)

        it("allow.body contains nested syntax", function()
          local config = {
            dots_in_keys = false,
            allow = {
              body = { "default.route" },
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            add = {body = {},},
          }

          local expected = { default = { route = data.default.route } }
          execute(config, expected)
        end)
      end)

    end)

    describe("with index", function()
      describe("remove", function ()
        it("index", function()
          local config = {
            dots_in_keys = false,
            remove = {
              body = {"default.plugins[2].order"},
            },
            rename = {body = {},},
            replace = {body = {},},
            add = {body = {},},
            append = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          expected['default']['plugins'][2]['order'] = nil

          execute(config, expected)
        end)

        it("[*]", function()
          local config = {
            dots_in_keys = false,
            remove = {
              body = {"default.plugins[*].order"},
            },
            rename = {body = {},},
            replace = {body = {},},
            add = {body = {},},
            append = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          for _, value in ipairs(expected['default']['plugins']) do
            value['order'] = nil
          end

          execute(config, expected)
        end)
      end)

      describe("rename", function()
        it("index", function()
          local config = {
            dots_in_keys = false,
            rename = {
              body = {"default.plugins[2].order:default.plugins[2].priority"},
            },
            remove = {body = {},},
            replace = {body = {},},
            add = {body = {},},
            append = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          local value = expected['default']['plugins'][2]['order']
          expected['default']['plugins'][2]['order'] = nil
          expected['default']['plugins'][2]['priority'] = value

          execute(config, expected)
        end)

        it("[*]", function()
          local config = {
            dots_in_keys = false,
            rename = {
              body = {"default.plugins[*].order:default.plugins[*].priority"},
            },
            remove = {body = {},},
            replace = {body = {},},
            add = {body = {},},
            append = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          for _, plugin in ipairs(expected['default']['plugins']) do
            local value = plugin['order']
            plugin['order'] = nil
            plugin['priority'] = value
          end

          execute(config, expected)
        end)
      end)

      describe("replace", function()
        it("index", function ()
          local config = {
            dots_in_keys = false,
            replace = {
              body = {"default.plugins[2].order:1000"},
              json_types = {"number"},
            },
            rename = {body = {},},
            remove = {body = {},},
            add = {body = {},},
            append = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          expected['default']['plugins'][2]['order'] = 1000

          execute(config, expected)
        end)

        it("[*]", function ()
          local config = {
            dots_in_keys = false,
            replace = {
              body = {"default.plugins[*].order:1000"},
              json_types = {"number"},
            },
            rename = {body = {},},
            remove = {body = {},},
            add = {body = {},},
            append = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          for _, plugin in ipairs(expected['default']['plugins']) do
            plugin['order'] = 1000
          end

          execute(config, expected)
        end)
      end)

      describe("add", function()
        it("index", function ()
          local config = {
            dots_in_keys = false,
            add = {
              body = {"default.plugins[2].type:add"},
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            append = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          expected['default']['plugins'][2]['type'] = "add"

          execute(config, expected)
        end)

        it("[*]", function ()
          local config = {
            dots_in_keys = false,
            add = {
              body = {"default.plugins[*].type:add"},
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            append = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          for _, plugin in ipairs(expected['default']['plugins']) do
            plugin['type'] = "add"
          end

          execute(config, expected)
        end)
      end)

      describe("append", function ()
        it("index", function ()
          local config = {
            dots_in_keys = false,
            append = {
              body = {"default.plugins[2].type:add"},
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            add = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          expected['default']['plugins'][2]['type'] = {"add"}

          execute(config, expected)
        end)

        it("[*]", function ()
          local config = {
            dots_in_keys = false,
            append = {
              body = {"default.plugins[*].name:add"},
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            add = {body = {},},
          }
          local expected = utils.cycle_aware_deep_copy(data)
          for _, plugin in ipairs(expected['default']['plugins']) do
            plugin['name'] = {plugin['name'], "add"}
          end

          execute(config, expected)
        end)
      end)

      describe("allow", function()
        it("allow.body contains nested syntax with index *", function()
          local config = {
            dots_in_keys = false,
            allow = {
              body = { "default.plugins[*].name" },
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            add = {body = {},},
          }

          local expected = {
            default = {
              plugins = {
                { name = "acl" },
                { name = "transformer" },
                { name = "authenticator" },
              },
            }
          }

          execute(config, expected)
        end)

        it("allow.body contains nested syntax with index i", function()
          local config = {
            dots_in_keys = false,
            allow = {
              body = { "default.plugins[2].name" },
            },
            rename = {body = {},},
            remove = {body = {},},
            replace = {body = {},},
            add = {body = {},},
          }

          local expected = {
            default = {
              plugins = {
                ngx.null,
                { name = "transformer" },
              },
            }
          }

          execute(config, expected)
        end)
      end)
    end)

    describe("invalid paths", function()
      it("accesing an array with non-index", function()
        local config = {
          dots_in_keys = false,
          remove = {
            body = {"default.plugins.name"},
          },
          rename = {body = {},},
          replace = {body = {},},
          add = {body = {},},
          append = {body = {},},
        }
        execute(config, data)
      end)

      it("accesing an map using index", function ()
        local config = {
          dots_in_keys = false,
          remove = {
            body = {"kong.route[1].name"},
          },
          rename = {body = {},},
          replace = {body = {},},
          add = {body = {},},
          append = {body = {},},
        }
        execute(config, data)
      end)
    end)
  end)
end
