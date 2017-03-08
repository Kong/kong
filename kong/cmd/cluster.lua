local log = require "kong.cmd.utils.log"
local Serf = require "kong.serf"
local pl_path = require "pl.path"
local pl_table = require "pl.tablex"
local DAOFactory = require "kong.dao.factory"
local conf_loader = require "kong.conf_loader"

local KEYS_COMMANDS = { "list", "install", "use", "remove" }

local function execute(args)
  if args.command == "keygen" then
    local conf = assert(conf_loader(args.conf))
    local dao = assert(DAOFactory.new(conf))
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
  local conf = assert(conf_loader(default_conf.kong_env))
  local dao = assert(DAOFactory.new(conf))
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
  elseif args.command == "keys" then
    assert(pl_table.find(KEYS_COMMANDS, args[1]), "invalid command")
    assert(args[1] == "list" or #args == 2, "missing key")

    print(assert(serf:keys("-"..args[1], args[2])))
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
 keys install <key>         Install a new key onto Kong's internal keyring. This
                            will enable the key for decryption. The key will not
                            be used to encrypt messages until the primary key is
                            changed.
 keys use <key>             Change the primary key used for encrypting messages.
                            All nodes in the cluster must already have this key
                            installed if they are to continue communicating with
                            eachother.
 keys remove <key>          Remove a key from Kong's internal keyring. The key
                            being removed may not be the current primary key.   
 keys list                  List all currently known keys in the cluster. This
                            will ask all nodes in the cluster for a list of keys
                            and dump a summary containing each key and the
                            number of members it is installed on to the console.

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
    ["force-leave"] = true,
    keys = true
  }
}
