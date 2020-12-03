-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong_global = require "kong.global"
local conf_loader = require "kong.conf_loader"
local DB = require "kong.db"
local ee = require "kong.enterprise_edition"


local function run_file(f, args)
  _G.args = args
  local func, err = loadfile(f, "t")
  if func then
    func()
    return true
  else
    print("Compilation error:", err)
  end
end


local function execute(args)
  _G.kong = kong_global.new()
  local config = assert(conf_loader(args.config, ee.license_conf()))

  kong_global.init_pdk(_G.kong, config, nil) -- nil: latest PDK
  local db = assert(DB.new(config))
  kong.db = db
  assert(db:init_connector())
  assert(db:connect())

  kong.db.plugins:load_plugin_schemas(config.loaded_plugins)

  assert(run_file(args[1], args))
end

return {
  lapp = [[
Usage: kong runner file.lua [args]

Execute a lua file in a kong node. The `kong` variable is available to
reach the DAO, PDK, etc. The variable `args` can be used to access all
arguments (args[1] being the lua filename bein run).

Options:
]],
  execute = execute,
}
