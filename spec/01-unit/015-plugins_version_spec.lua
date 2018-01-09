local conf_loader = require "kong.conf_loader"


describe("Plugins", function()
  local plugins

  setup(function()
    local conf = assert(conf_loader())

    plugins = {}

    for plugin in pairs(conf.plugins) do
      local handler = require("kong.plugins." .. plugin .. ".handler")
      table.insert(plugins, {
        name    = plugin,
        handler = handler
      })
    end
  end)

  it("contain a VERSION field", function()
    for _, plugin in ipairs(plugins) do
      assert.not_nil(plugin.handler.VERSION)
    end
  end)
end)
