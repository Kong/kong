local Connector = require "kong.db.strategies.connector"

local FakeConnector = setmetatable({}, { __index = Connector })
FakeConnector.__index = FakeConnector

function FakeConnector.new()
  return setmetatable({}, FakeConnector)
end

function FakeConnector:reset()
  return true
end

function FakeConnector:truncate()
  return true
end

return FakeConnector
