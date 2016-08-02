local log = require "kong.cmd.utils.log"
local Serf = require "kong.serf"
local pl_path = require "pl.path"
local DAOFactory = require "kong.dao.factory"
local conf_loader = require "kong.conf_loader"

local function execute(args)
  if args.command == "keygen" then
    local conf = assert(conf_loader(args.conf))
    local dao = DAOFactory(conf)
    local serf = Serf.new(conf, dao)
    print(assert(serf:keygen()))
    return
  end

  -- retrieve default prefix or use given one
  local default_conf = assert(conf_loader(nil, {
    prefix = args.prefix
  }))
  -- load <PREFIX>/kong.conf containing running node's config
  assert(pl_path.exists(default_conf.prefix),
         "no such prefix: "..default_conf.prefix)
  local conf = assert(conf_loader(default_conf.kong_conf))
  local dao = DAOFactory(conf)
  local serf = Serf.new(conf, dao)

  if args.command == "members" then
    local members = assert(serf:members(true))
    for _, v in ipairs(members) do
      print(string.format("%s\t%s\t%s", v.name, v.addr, v.status))
    end
  elseif args.command == "reachability" then
    print(assert(serf:reachability()))
  elseif args.command == "force-leave" then
    local node_name = args[1]
    assert(node_name ~= nil, "must specify the name of the node to leave")
    log("force-leaving %s", node_name)
    assert(serf:force_leave(node_name))
    log("left node %s", node_name)
  end
end

local lapp = [[
Usage: kong cluster COMMAND [OPTIONS]

Manage Kong's clustering capabilities.

The available commands are:
 keygen -c                  Generate an encryption key for intracluster traffic.
                            See 'cluster_encrypt_key' setting
 members -p                 Show members of this cluster and their state.
 reachability -p            Check if the cluster is reachable.
 force-leave -p <node_name> Forcefully remove a node from the cluster (useful
                            if the node is in a failed state).


Options:
 -c,--conf   (optional string) configuration file
 -p,--prefix (optional string) prefix Kong is running at
]]

return {
  lapp = lapp,
  execute = execute,
  sub_commands = {
    keygen = true,
    members = true,
    reachability = true,
    ["force-leave"] = true
  }
}
