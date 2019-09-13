local kong_global = require "kong.global"
local conf_loader = require "kong.conf_loader"
local DB = require "kong.db"


local function run_file(f, kong)
  local func, err = loadfile(f, "t")
  if func then
    func(kong)
    return true
  else
    print("Compilation error:", err)
  end
end


local function execute(args)
  _G.kong = kong_global.new()
  local conf = assert(conf_loader(args.conf))
  kong_global.init_pdk(_G.kong, conf, nil) -- nil: latest PDK
  local db = assert(DB.new(conf))
  kong.db = db
  assert(db:init_connector())
  assert(db:connect())
  assert(run_file(args[1], kong))
end

return {
  lapp = [[
Usage: kong runner file.lua

Execute a lua file in a kong node. the `kong` variable is available to
reach the DAO, PDK, etc. ]],

execute = execute, }
