-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

require "spec.helpers" -- initializes 'kong' global for plugins
local conf_loader = require "kong.conf_loader"


describe("Plugins", function()
  local plugins

  lazy_setup(function()
    local conf = assert(conf_loader())

    plugins = {}

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf, nil)

    for plugin in pairs(conf.loaded_plugins) do
      local handler = require("kong.plugins." .. plugin .. ".handler")
      table.insert(plugins, {
        name    = plugin,
        handler = handler
      })
    end
  end)

  it("contain a VERSION field", function()
    for _, plugin in ipairs(plugins) do
      assert(plugin.handler.VERSION,
             "Expected a `VERSION` field in `kong.plugins." ..
             plugin.name .. ".handler.lua`")
    end
  end)
end)
