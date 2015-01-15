-- Copyright (C) Mashape, Inc.

local cassandra = require "cassandra"
local stringy = require "stringy"
local Object = require "classic"

local Client = Object:extend()

function Client:new(configuration)
  self._configuration = configuration

  -- Cache the prepared statements if already prepared
  self._stmt_cache = {}
end

-- Utility function to execute queries
-- @param cmd The CQL command to execute
-- @param args The arguments of the command
-- @return the result of the operation
function Client:query(cmd, args, disable_keyspace)
  -- Creates a new session
  local session = cassandra.new()

  -- Sets the timeout for the subsequent operations
  session:set_timeout(self._configuration.timeout)

  -- Connects to Cassandra
  local connected, err = session:connect(self._configuration.host, self._configuration.port)
  if not connected then
    return nil, err
  end

  -- Sets the default keyspace
  if not disable_keyspace then
    local ok, err = session:set_keyspace(self._configuration.keyspace)
    if not ok then
      return nil, err
    end
  end

  local result, err = nil

  local cmds = stringy.split(cmd, ";")
  for i,v in ipairs(cmds) do
    if stringy.strip(v) ~= "" then
      local stmt = self._stmt_cache[v]
      if not stmt then
        local new_stmt, err = session:prepare(v)
        if err then
          return nil, err
        end
        self._stmt_cache[v] = new_stmt
        stmt = new_stmt
      end

      -- Executes the command
      result, err = session:execute(stmt, args)
      if result == nil and err then
        return nil, err
      end
    end
  end

  -- Puts back the connection in the nginx pool
  local ok, err = session:set_keepalive(self._configuration.keepalive)
  if not ok and err ~= "luasocket does not support reusable sockets" then
    return nil, err
  end

  return result
end

return Client