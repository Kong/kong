local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local Serf = require "kong.serf"
local log = require "kong.cmd.utils.log"

local function execute(args)
  local conf = assert(conf_loader(args.conf))
  local dao = DAOFactory(conf)
  local serf = Serf.new(conf, conf.prefix, dao)

  if args.command == "members" then
    local members = assert(serf:members(true))
    for _, v in ipairs(members) do
      print(string.format("%s\t%s\t%s", v.name, v.addr, v.status))
    end
  elseif args.command == "keygen" then
    print(assert(serf:keygen()))
  elseif args.command == "reachability" then
    print(assert(serf:reachability()))
  elseif args.command == "force-leave" then
    local node_name = args[1]
    assert(node_name ~= nil, "you need to specify the node name to leave")
    log("force-leaving %s", node_name)
    assert(serf:force_leave(node_name))
    log("left node %s", node_name)
  end
end

local lapp = [[
Usage: kong cluster COMMAND [OPTIONS]

The available commands are:
 members
 force-leave <node_name>
 keygen
 reachability

Options:
 -c,--conf (optional string) configuration file
]]

return {
  lapp = lapp,
  execute = execute,
  sub_commands = {
    members = true,
    keygen = true,
    reachability = true,
    ["force-leave"] = true
  }
}
