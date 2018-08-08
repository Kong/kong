local fmt = string.format


local Connector = {}


function Connector:init()
  -- nop by default
  return true
end


function Connector:connect()
  error(fmt("connect() not implemented for '%s' strategy", self.database))
end


function Connector:setkeepalive()
  error(fmt("setkeepalive() not implemented for '%s' strategy", self.database))
end


function Connector:query()
  error(fmt("query() not implemented for '%s' strategy", self.database))
end


function Connector:reset()
  error(fmt("reset() not implemented for '%s' strategy", self.database))
end


function Connector:truncate()
  error(fmt("truncate() not implemented for '%s' strategy", self.database))
end


function Connector:setup_locks()
  error(fmt("setup_locks() not implemented for '%s' strategy", self.database))
end


function Connector:insert_lock()
  error(fmt("insert_lock() not implemented for '%s' strategy", self.database))
end


function Connector:read_lock()
  error(fmt("read_lock() not implemented for '%s' strategy", self.database))
end


function Connector:remove_lock()
  error(fmt("remove_lock() not implemented for '%s' strategy", self.database))
end


return Connector
