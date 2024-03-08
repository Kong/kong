-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local conf_loader = require "kong.conf_loader"
local topsort_plugins = require("kong.db.schema.topsort_plugins")

local function sort_by_handler_priority(a, b)
  local prio_a = a.plugin.handler.PRIORITY or 0
  local prio_b = b.plugin.handler.PRIORITY or 0
  if prio_a == prio_b and not
      (prio_a == 0 or prio_b == 0) then
    return a.plugin.name > b.plugin.name
  end
  return prio_a > prio_b
end


local fmt = string.format

local function build_int_indexed_list(lst)
  local n = {}
  local c = 1
  for _, elem in pairs(lst) do
    n[c] = elem
    c = c + 1
  end
  -- ensure that we get the same order as we get from the pluginsiterator
  table.sort(n, sort_by_handler_priority)
  return n
end


describe("Plugins", function()
  local plugins

  lazy_setup(function()
    local conf = assert(conf_loader(nil, {
      plugins = "bundled",
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf, nil)

    plugins = {}

    -- require "spec.helpers" -- initializes 'kong' global for plugins
    for plugin in pairs(conf.loaded_plugins) do
      if plugin ~= "prometheus" then
        local handler = require("kong.plugins." .. plugin .. ".handler")
        table.insert(plugins, {
          name    = plugin,
          handler = handler,
          -- subphase_order function expects a different structure
          plugin  = { handler = handler },
          config  = {}
        })
      end
    end
  end)

  it("don't have identical `PRIORITY` fields", function()
    local priorities = {}

    for _, plugin in ipairs(plugins) do
      local priority = plugin.handler.PRIORITY
      assert.not_nil(priority)

      if priorities[priority] then
        -- ignore colliding priorities for "advanced" and "enc" plugins
        if plugin.name:gsub("%-advanced", "") ~= priorities[priority]:gsub("%-advanced", "")
           and plugin.name:gsub("%-enc", "") ~= priorities[priority]:gsub("%-enc", "") then
            assert.fail(fmt("plugins have the same priority: '%s' and '%s' (%d)",
                        priorities[priority], plugin.name, priority))
        end
      end

      priorities[priority] = plugin.name
    end
  end)

  for _ = 1, 100 do
    it("tests topsort #simple", function()
      local plugins_meta = {
        ["key-auth"] = {
          plugin = {
            name = "key-auth",
            handler = {
              PRIORITY = 1250
            },
          },
          config = {},
        },
        ["rate-limiting"] = {
          plugin = {
            name = "rate-limiting",
            handler = {
              PRIORITY = 910
            }
          },
          config = {
            ordering = {
              -- run `self` before `key-auth`
              before = {
                access = {
                  "key-auth"
                }
              }
            }
          },
        },
      }
      local ordered, err = topsort_plugins(plugins_meta, build_int_indexed_list(plugins_meta))
      assert.is_nil(err)
      assert.is_table(ordered[1].plugin)
      assert.same("rate-limiting", ordered[1].plugin.name)
      assert.is_table(ordered[2].plugin)
      assert.same("key-auth", ordered[2].plugin.name)
    end)

    it("tests topsort #advanced", function()
      local plugins_meta = {
        ["openid-connect"] = {
          plugin = {
            name = "openid-connect",
            handler = {
              PRIORITY = 1050
            }
          },
          config = {
            ordering = {
              before = {
                access = {
                  "custom-plugin"
                }
              }
            }
          }
        },
        ["request-validator"] = {
          plugin = {
            name = "request-validator",
            handler = {
              PRIORITY = 999
            }
          },
          config = {
            ordering = {
              after = {
                access = {
                  "custom-plugin"
                }
              }
            }
          },
        },
        ["custom-plugin"] = {
          plugin = {
            name = "custom-plugin",
            handler = {
              PRIORITY = 400
            }
          },
          config = {
            ordering = {
              before = {
                access = {
                  "request-validator"
                }
              }
            }
          },
        },
      }
      local ordered, err = topsort_plugins(plugins_meta, build_int_indexed_list(plugins_meta))
      assert.is_nil(err)
      assert.is_table(ordered[1].plugin)
      assert.same("openid-connect", ordered[1].plugin.name)
      assert.is_table(ordered[2].plugin)
      assert.same("custom-plugin", ordered[2].plugin.name)
      assert.is_table(ordered[3].plugin)
      assert.same("request-validator", ordered[3].plugin.name)
    end)

    it("tests topsort advanced++", function()
      -- rate-limit, request-size-limit, ip-restriction, openid-connect, request-transform, jq
      local plugins_meta = {
        ["openid-connect"] = {
          plugin = {
            name = "openid-connect",
            handler = {
              PRIORITY = 1050
            }
          },
          config = {
            ordering = {
              after = {
                access = {
                  "ip-restriction"
                }
              },
              before = {
                access = {
                  "request-transform"
                }
              }
            }
          }
        },
        ["rate-limiting"] = {
          plugin = {
            name = "rate-limiting",
            handler = {
              PRIORITY = 910
            }
          },
          config = {
            ordering = {
              before = {
                access = {
                  "request-size-limit"
                }
              }
            }
          },
        },
        ["ip-restriction"] = {
          plugin = {
            name = "ip-restriction",
            handler = {
              PRIORITY = 990
            }
          },
          config = {
            ordering = {
              before = {
                access = {
                  "openid-connect"
                }
              }
            }
          },
        },
        ["request-size-limit"] = {
          plugin = {
            name = "request-size-limit",
            handler = {
              PRIORITY = 951
            }
          },
          config = {
            ordering = {
              before = {
                access = {
                  "ip-restriction"
                }
              }
            }
          },
        },
        ["jq"] = {
          plugin = {
            name = "jq",
            handler = {
              PRIORITY = 811
            }
          },
          config = {
            ordering = {
              after = {
                access = {
                  "request-transform"
                }
              }
            }
          }
        },
        ["request-transform"] = {
          plugin = {
            name = "request-transform",
            handler = {
              PRIORITY = 801
            }
          },
          config = {}
        },
      }
      local ordered, err = topsort_plugins(plugins_meta, build_int_indexed_list(plugins_meta))
      assert.is_nil(err)
      assert.is_table(ordered[1].plugin)
      assert.same("rate-limiting", ordered[1].plugin.name)
      assert.is_table(ordered[2].plugin)
      assert.same("request-size-limit", ordered[2].plugin.name)
      assert.is_table(ordered[3].plugin)
      assert.same("ip-restriction", ordered[3].plugin.name)
      assert.is_table(ordered[4].plugin)
      assert.same("openid-connect", ordered[4].plugin.name)
      assert.is_table(ordered[5].plugin)
      assert.same("request-transform", ordered[5].plugin.name)
      assert.is_table(ordered[6].plugin)
      assert.same("jq", ordered[6].plugin.name)
    end)

    it("tests topsort no markers", function()
      local plugins_meta = {
        ["openid-connect"] = {
          plugin = {
            name = "openid-connect",
            handler = {
              PRIORITY = 801,
            }
          },
          config = {}
        },
        ["request-validator"] = {
          plugin = {
            name = "request-validator",
            handler = {
              PRIORITY = 999,
            }
          },
          config = {},
        },
        ["custom-plugin"] = {
          plugin = {
            name = "custom-plugin",
            handler = {
              PRIORITY = 400,
            }
          },
          config = {},
        },
      }
      local indexed_plugin_list = build_int_indexed_list(plugins_meta)
      local ordered, err = topsort_plugins(plugins_meta, indexed_plugin_list)
      assert.is_nil(err)
      assert.is_same(3, #ordered)
      -- ensure that the plugins go the same order _in_ as they go out.
      assert.same(indexed_plugin_list[1].plugin.name, ordered[1].plugin.name)
      assert.same(indexed_plugin_list[2].plugin.name, ordered[2].plugin.name)
      assert.same(indexed_plugin_list[3].plugin.name, ordered[3].plugin.name)
    end)

    it("tests topsort circular markers", function()
      local plugins_meta = {
        ["openid-connect"] = {
          plugin = {
            name = "openid-connect",
            handler = {
              PRIORITY = 1050
            }
          },
          config = {
            ordering = {
              before = {
                access = {
                  "custom-plugin"
                }
              }
            }
          }
        },
        ["custom-plugin"] = {
          plugin = {
            name = "custom-plugin",
            handler = {
              PRIORITY = 400
            }
          },
          config = {
            ordering = {
              before = {
                access = {
                  "openid-connect"
                }
              }
            }
          },
        },
      }
      local ordered, err = topsort_plugins(plugins_meta, build_int_indexed_list(plugins_meta))
      assert.is_same("There is a circular dependency in the graph. It is not possible to derive a topological sort.", err)
      assert.is_nil(ordered)
    end)

    it("tests topsort #partial markers", function()
      local plugins_meta = {
        -- ORIGINALLY, this should've been the first in the list,
        -- it has the `before -> custom_plugin` marker
        ["openid-connect"] = {
          plugin = {
            name = "openid-connect",
            handler = {
              PRIORITY = 1050,
            }
          },
          config = {
            ordering = {
              before = {
                access = {
                  "custom-plugin"
                }
              }
            }
          }
        },
        -- ORIGINALLY it runs second.
        -- Now it has markers to indicate it should run _after_
        -- the oidc, which is already the case
        -- but also after the custom plugin which is last.
        -- This should now run _last_
        ["request-validator"] = {
          plugin = {
            name = "request-validator",
            handler = {
              PRIORITY = 999,
            }
          },
          config = {
            ordering = {
              -- from "oidc" to `self`
              -- from "custom" to `self`
              after = {
                access = {
                  "openid-connect",
                  "custom-plugin"
                }
              }
            }
          },
        },
        -- ORIGINALLY this should run before the `custom-plugin` as well as the `openid-connect`
        -- Now, this should be the first in the list as the `request-validator` moves down the list
        ["request-size-validator"] = {
          plugin = {
            name = "request-size-validator",
            handler = {
              PRIORITY = 951,
            }
          },
          config = {},
        },
        -- ORIGINALLY, this runs after the request-size-validator
        -- but the OIDC plugin has an `before -> custom_plugin` marker
        -- The request-validator has an `after -> custom_plugin` marker
        ["custom-plugin"] = {
          plugin = {
            name = "custom-plugin",
            handler = {
              PRIORITY = 801,
            }
          },
          config = {},
        },
      }
      -- The final order should be "oidc -> custom-plugin -> request-validator -> request-size-validator"
      local indexed_plugin_list = build_int_indexed_list(plugins_meta)
      assert.same(4, #indexed_plugin_list)
      local ordered, err = topsort_plugins(plugins_meta, indexed_plugin_list)
      assert.is_nil(err)
      assert.same(4, #ordered)
      assert.same("openid-connect", ordered[1].plugin.name)
      assert.same("custom-plugin", ordered[2].plugin.name)
      assert.same("request-validator", ordered[3].plugin.name)
      assert.same("request-size-validator", ordered[4].plugin.name)
    end)

    it("tests topsort markers reversed", function()
      local plugins_meta = {
        ["openid-connect"] = {
          plugin = {
            name = "openid-connect",
            handler = {
              PRIORITY = 1050
            }
          },
          config = {
            ordering = {
              after = {
                access = {
                  "custom-plugin"
                }
              },
              before = {
                access = {
                  "request-size-limiting"
                }
              }
            }
          },
        },
        ["request-validator"] = {
          plugin = {
            name = "request-validator",
            handler = {
              PRIORITY = 999
            }
          },
          config = {},
        },
        ["request-size-limiting"] = {
          plugin = {
            name = "request-size-limiting",
            handler = {
              PRIORITY = 951
            }
          },
          config = {},
        },
        ["custom-plugin"] = {
          plugin = {
            name = "custom-plugin",
            handler = {
              PRIORITY = 400
            }
          },
          config = {},
        },
      }
      local ordered, err = topsort_plugins(plugins_meta, build_int_indexed_list(plugins_meta))
      assert.is_nil(err)
      assert.is_same(4, #ordered)
      assert.same("custom-plugin", ordered[1].plugin.name)
      assert.same("openid-connect", ordered[2].plugin.name)
      assert.same("request-size-limiting", ordered[4].plugin.name)
      assert.same("request-validator", ordered[3].plugin.name)
    end)
  end
end)
