-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local conf_loader = require "kong.conf_loader"
local topsort_plugins = require("kong.db.schema.topsort_plugins")


local fmt = string.format

local function build_int_indexed_list(lst)
  local n = {}
  local c = 1
  for _, elem in pairs(lst) do
    n[c] = elem
    c = c+1
  end
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
          plugin = {handler = handler},
          config = {}
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
        assert.fail(fmt("plugins have the same priority: '%s' and '%s' (%d)",
                        priorities[priority], plugin.name, priority))
      end

      priorities[priority] = plugin.name
    end
  end)

for i=1,100 do
  it("tests topsort simple", function ()
    local plugins_meta = {
      ["key-auth"] = {
        plugin = {
          name = "key-auth",
        },
        config = {
          before = {}
        },
      },
      ["rate-limiting"] = {
        plugin = {
          name = "rate-limiting",
        },
        config = {
          ordering = {
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
    assert("rate-limiting", ordered[1].id)
    assert("key-auth", ordered[2].id)
  end)

  it("tests topsort advanced", function ()
    local plugins_meta = {
      ["custom-plugin"] = {
        plugin = {
          name = "custom-plugin",
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
      ["request-validator"] = {
        plugin = {
          name = "request-validator",
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
      ["openid-connect"] = {
        plugin = {
          name = "openid-connect",
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
      }
    }
    local ordered, err = topsort_plugins(plugins_meta, build_int_indexed_list(plugins_meta))
    assert.is_nil(err)
    assert("openid-connect", ordered[1].id)
    assert("custom-plugin", ordered[2].id)
    assert("request-validator", ordered[3].id)
  end)

  it("tests topsort advanced++", function ()
    -- rate-limit, request-size-limit, ip-restriction, openid-connect, request-transform, jq
    local plugins_meta = {
      ["jq"] = {
        plugin = {
          name = "jq",
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
      ["rate-limiting"] = {
        plugin = {
          name = "rate-limiting",
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
      ["request-transform"] = {
        plugin = {
          name = "request-transform",
        },
        config = {}
      },
      ["openid-connect"] = {
        plugin = {
          name = "openid-connect",
        },
        config = {
          ordering = {
            after = {
              access = {
                "ip-restriction" -- not necessary but should not change anything
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

    }
    local ordered, err = topsort_plugins(plugins_meta, build_int_indexed_list(plugins_meta))
    assert.is_nil(err)
    assert("rate-limiting", ordered[1].id)
    assert("request-size-limit", ordered[2].id)
    assert("ip-restriction", ordered[3].id)
    assert("openid-connect", ordered[4].id)
    assert("request-transform", ordered[5].id)
    assert("jq", ordered[6].id)
  end)

  it("tests topsort no markers", function ()
    local plugins_meta = {
      ["openid-connect"] = {
        plugin = {
          name = "openid-connect",
        },
        config = {}
      },
      ["request-validator"] = {
        plugin = {
          name = "request-validator"
        },
        config = {},
      },
      ["custom-plugin"] = {
        plugin = {
          name = "custom-plugin",
        },
        config = {},
      },
    }
    local ordered, err = topsort_plugins(plugins_meta, build_int_indexed_list(plugins_meta))
    assert.is_nil(err)
    assert("openid-connect", ordered[1].id)
    assert("custom-plugin", ordered[2].id)
    assert("request-validator", ordered[3].id)
  end)

  it("tests topsort circular markers", function ()
    local plugins_meta = {
      ["openid-connect"] = {
        plugin = {
          name = "openid-connect",
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

  it("tests topsort partial markers", function ()
    local plugins_meta = {
      ["custom-plugin"] = {
        plugin = {
          name= "custom-plugin",
        },
        config = {},
      },
      ["openid-connect"] = {
        plugin = {
          name= "openid-connect",
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
        plugin ={
          name= "request-validator",
        },
        config = {},
      },
      ["request-size-validator"] = {
        plugin ={
          name= "request-size-validator",
        },
        config = {},
      },
    }
    -- No before, after means no sorting -> {}
    local ordered, err = topsort_plugins(plugins_meta, build_int_indexed_list(plugins_meta))
    assert.is_nil(err)
    assert("openid-connect", ordered[1].id)
    assert("custom-plugin", ordered[2].id)
    assert("request-validator", ordered[3].id)
    assert("request-size-validator", ordered[4].id)
 end)

  it("tests topsort partial markers reversed", function ()
    local plugins_meta = {
      ["openid-connect"] = {
        plugin = {
          name = "openid-connect",
        },
        config = {},
      },
      ["custom-plugin"] = {
        plugin = {
          name = "custom-plugin",
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
      ["request-validator"] = {
        plugin = {
          name = "request-validator",
        },
        config = {},
      },
      ["request-size-validator"] = {
        plugin = {
          name = "request-size-validator",
        },
        config = {},
      },
    }
    local ordered, err = topsort_plugins(plugins_meta, build_int_indexed_list(plugins_meta))
    assert.is_nil(err)
    assert("custom-plugin", ordered[1].id)
    assert("openid-connect", ordered[2].id)
    assert("request-validator", ordered[3].id)
    assert("request-size-validator", ordered[4].id)
  end)
end
end)
