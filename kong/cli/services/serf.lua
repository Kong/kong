local cluster_utils = require "kong.tools.cluster"
local BaseService = require "kong.cli.services.base_service"
local dao_loader = require "kong.tools.dao_loader"
local stringy = require "stringy"
local logger = require "kong.cli.utils.logger"
local cjson = require "cjson"
local IO = require "kong.tools.io"

local Serf = BaseService:extend()

local SERVICE_NAME = "serf"
local START_TIMEOUT = 10
local EVENT_NAME = "kong"

function Serf:new(configuration)
  local nginx_working_dir = configuration.nginx_working_dir

  self._configuration = configuration
  local path_prefix = nginx_working_dir
                        ..(stringy.endswith(nginx_working_dir, "/") and "" or "/")
  self._script_path = path_prefix.."serf_event.sh"
  self._log_path = path_prefix.."serf.log"
  self._dao_factory = dao_loader.load(self._configuration)
  Serf.super.new(self, SERVICE_NAME, nginx_working_dir)
end

function Serf:_get_cmd()
  local cmd, err = Serf.super._get_cmd(self, {}, function(path)
    local res, code = IO.os_execute(path.." version")
    if code == 0 then
      return res:match("^Serf v0.7.0")
    end

    return false
  end)

  return cmd, err
end

function Serf:prepare()
  -- Create working directory if missing
  local ok, err = Serf.super.prepare(self, self._configuration.nginx_working_dir)
  if not ok then
    return nil, err
  end

  -- Create serf event handler
  local luajit_path = BaseService.find_cmd("luajit")
  if not luajit_path then
    return nil, "Can't find luajit"
  end

  local script = [[
#!/bin/sh
PAYLOAD=`cat` # Read from stdin

if [ "$SERF_EVENT" != "user" ]; then
  PAYLOAD="{\"type\":\"${SERF_EVENT}\",\"entity\": \"${PAYLOAD}\"}"
fi

echo $PAYLOAD > /tmp/payload

COMMAND='require("kong.tools.http_client").post("http://]]..self._configuration.admin_api_listen..[[/cluster/events/", ]].."[=['${PAYLOAD}']=]"..[[, {["content-type"] = "application/json"})'

echo $COMMAND | ]]..luajit_path..[[
]]
  local _, err = IO.write_to_file(self._script_path, script)
  if err then
    return false, err
  end

  -- Adding executable permissions
  local res, code = IO.os_execute("chmod +x "..self._script_path)
  if code ~= 0 then
    return false, res
  end

  -- Create the unique identifier if it doesn't exist
  local _, err = cluster_utils.create_node_identifier(self._configuration)
  if err then
    return false, err
  end

  return true
end

function Serf:_join_node(address)
  local _, err = self:invoke_signal("join", {address})
  if err then
    return false
  end
  return true
end

function Serf:_members()
  local res, err = self:invoke_signal("members", {["-format"] = "json"})
  if err then
    return nil, err
  end

  return cjson.decode(res).members
end

function Serf:_autojoin(current_node_name)
  if self._configuration.cluster["auto-join"] then
    logger:info("Trying to auto-join Kong nodes, please wait..")

    -- Delete current node just in case it was there (due to an inconsistency caused by a crash)
    local _, err = self._dao_factory.nodes:delete({
      name = current_node_name
    })
    if err then
      return false, tostring(err)
    end

    local nodes, err = self._dao_factory.nodes:find_all()
    if err then
      return false, tostring(err)
    else
      if #nodes == 0 then
        logger:info("No other Kong nodes were found in the cluster")
      else
        -- Sort by newest to oldest (although by TTL would be a better sort)
        table.sort(nodes, function(a, b)
          return a.created_at > b.created_at
        end)

        local joined
        for _, v in ipairs(nodes) do
          if self:_join_node(v.cluster_listening_address) then
            logger:info("Successfully auto-joined "..v.cluster_listening_address)
            joined = true
            break
          else
            logger:warn("Cannot join "..v.cluster_listening_address..". If the node does not exist anymore it will be automatically purged.")
          end
        end
        if not joined then
          logger:warn("Could not join the existing cluster")
        end
      end
    end
  end
  return true
end

function Serf:_add_node()
  local members, err = self:_members()
  if err then
    return false, err
  end

  local name = cluster_utils.get_node_identifier(self._configuration)
  local addr
  for _, member in ipairs(members) do
    if member.name == name then
      addr = member.addr
      break
    end
  end

  if not addr then
     return false, "Can't find current member address"
  end

  local _, err = self._dao_factory.nodes:insert({
    name = name,
    cluster_listening_address = stringy.strip(addr)
  }, {ttl = self._configuration.cluster.ttl_on_failure})
  if err then
    return false, err
  end

  return true
end

function Serf:start()
  if self:is_running() then
    return nil, SERVICE_NAME.." is already running"
  end

  local cmd, err = self:_get_cmd()
  if err then
    return nil, err
  end

  local node_name = cluster_utils.get_node_identifier(self._configuration)

  -- Prepare arguments
  local cmd_args = {
    ["-bind"] = self._configuration.cluster_listen,
    ["-rpc-addr"] = self._configuration.cluster_listen_rpc,
    ["-advertise"] = self._configuration.cluster.advertise,
    ["-encrypt"] = self._configuration.cluster.encrypt,
    ["-log-level"] = "err",
    ["-profile"] = self._configuration.cluster.profile,
    ["-node"] = node_name,
    ["-event-handler"] = "member-join,member-leave,member-failed,member-update,member-reap,user:"..EVENT_NAME.."="..self._script_path
  }

  setmetatable(cmd_args, require "kong.tools.printable")
  local str_cmd_args = tostring(cmd_args)
  local res, code = IO.os_execute("nohup "..cmd.." agent "..str_cmd_args.." > "..self._log_path.." 2>&1 & echo $! > "..self._pid_file_path)
  if code == 0 then

    -- Wait for process to start, with a timeout
    local start = os.time()
    while not (IO.file_exists(self._log_path) and string.match(IO.read_file(self._log_path), "running") or (os.time() > start + START_TIMEOUT)) do
      -- Wait
    end

    if self:is_running() then
      logger:info(string.format([[serf ..............%s]], str_cmd_args))

      -- Auto-Join nodes
      local ok, err = self:_autojoin(node_name)
      if not ok then
        return nil, err
      end

      -- Adding node to nodes table
      return self:_add_node()
    else
      -- Get last error message
      local parts = stringy.split(IO.read_file(self._log_path), "\n")
      return nil, "Could not start serf: "..string.gsub(parts[#parts - 1], "==> ", "")
    end
  else
    return nil, res
  end
end

function Serf:invoke_signal(signal, args, no_rpc, skip_running_check)
  if not skip_running_check and not self:is_running() then
    return nil, SERVICE_NAME.." is not running"
  end

  local cmd, err = self:_get_cmd()
  if err then
    return nil, err
  end

  if not args then args = {} end
  setmetatable(args, require "kong.tools.printable")
  local res, code = IO.os_execute(cmd.." "..signal.." "..(no_rpc and "" or "-rpc-addr="..self._configuration.cluster_listen_rpc).." "..tostring(args), true)
  if code == 0 then
    return res
  else
    return false, res
  end
end

function Serf:event(t_payload)
  local args = {
    ["-coalesce"] = false,
    ["-rpc-addr"] = self._configuration.cluster_listen_rpc
  }
  setmetatable(args, require "kong.tools.printable")

  local encoded_payload = cjson.encode(t_payload)
  if string.len(encoded_payload) > 512 then
    -- Serf can't send a payload greater than 512 bytes
    return false, "Encoded payload is "..string.len(encoded_payload).." and it exceeds the limit of 512 bytes!"
  end

  return self:invoke_signal("event "..tostring(args).." kong", {"'"..encoded_payload.."'", "&"}, true)
end

function Serf:stop()
  logger:info("Leaving cluster..")
  local _, err = self:invoke_signal("leave")
  if err then
    return false, err
  else
    -- Remove the node from the datastore.
    -- This is useful when this is the only node running in the cluster.
    self._dao_factory.nodes:delete({
      name = cluster_utils.get_node_identifier(self._configuration)
    })

    -- Finally stop Serf
    Serf.super.stop(self, true)
  end
end

return Serf
