-- from the previous services.serf module, simply decoupled from
-- the Serf agent supervision logic.

local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local cjson = require "cjson.safe"
local log = require "kong.cmd.utils.log"
local fmt = string.format

local ok, _, stdout, stderr = pl_utils.executeex "/bin/hostname"
if not ok then error(stderr) end
local hostname = pl_stringx.strip(stdout)

local Serf = {}
Serf.__index = Serf

Serf.args_mt = {
  __tostring = function(t)
    local buf = {}
    for k, v in pairs(t) do buf[#buf+1] = k.." '"..v.."'" end
    return table.concat(buf, " ")
  end
}

function Serf.new(kong_config, dao)
  return setmetatable({
    node_name = hostname.."_"..kong_config.cluster_listen,
    config = kong_config,
    dao = dao
  }, Serf)
end

-- WARN: BAD, this is **blocking** IO. Legacy code from previous Serf
-- implementation that needs to be upgraded.
function Serf:invoke_signal(signal, args, no_rpc)
  args = args or {}
  if type(args) == "table" then
    setmetatable(args, Serf.args_mt)
  end
  local rpc = no_rpc and "" or "-rpc-addr="..self.config.cluster_listen_rpc
  local cmd = fmt("serf %s %s %s", signal, rpc, tostring(args))
  local ok, code, stdout = pl_utils.executeex(cmd)
  if not ok or code ~= 0 then return nil, stdout end

  return stdout
end

function Serf:join_node(address)
  return select(2, self:invoke_signal("join", address)) == nil
end

function Serf:members()
  local res, err = self:invoke_signal("members", {["-format"] = "json"})
  if not res then return nil, err end

  local json, err = cjson.decode(res)
  if not json then return nil, err end

  return json.members
end

function Serf:autojoin()
  -- Delete current node just in case it was there
  -- (due to an inconsistency caused by a crash)
  local _, err = self.dao.nodes:delete {name = self.node_name}
  if err then return nil, tostring(err) end

  local nodes, err = self.dao.nodes:find_all()
  if err then return nil, tostring(err)
  elseif #nodes == 0 then
    log.warn("could not auto-join the cluster: no nodes found")
  else
    -- Sort by newest to oldest (although by TTL would be a better sort)
    table.sort(nodes, function(a, b) return a.created_at > b.created_at end)

    local joined
    for _, v in ipairs(nodes) do
      if self:join_node(v.cluster_listening_address) then
        log("Successfully auto-joined %s", v.cluster_listening_address)
        joined = true
        break
      else
        log.warn("could not join %s, if the node does not exist anymore it will be automatically purged", v.cluster_listening_address)
      end
    end
    if not joined then
      log.warn("could not join the existing cluster")
    end
  end

  return true
end

function Serf:add_node()
  local members, err = self:members()
  if not members then return nil, err end

  local addr
  for _, member in ipairs(members) do
    if member.name == self.node_name then
      addr = member.addr
      break
    end
  end

  if not addr then
    return nil, "can't find current member address"
  end

  local _, err = self.dao.nodes:insert({
    name = self.node_name,
    cluster_listening_address = pl_stringx.strip(addr)
  }, {ttl = 3600})
  if err then return nil, tostring(err) end

  return true
end

function Serf:event(t_payload)
  local payload, err = cjson.encode(t_payload)
  if not payload then return nil, err end

  if #payload > 512 then
    -- Serf can't send a payload greater than 512 bytes
    return nil, "Encoded payload is "..#payload.." and exceeds the limit of 512 bytes!"
  end

  return self:invoke_signal("event -coalesce=false", " kong '"..payload.."'")
end

return Serf
