local type = type
local fmt = string.format


local Connector = {
  defaults = {
    pagination = {
      page_size     = 1000,
      max_page_size = 50000,
    },
  },
}


function Connector:init()
  -- nop by default
  return true
end


function Connector:init_worker()
  -- nop by default
  return true
end


function Connector:get_page_size(options)
  if type(options) == "table" and type(options.pagination) == "table" then
    return options.pagination.page_size
  end

  return self.defaults.pagination.page_size
end


do
  local past_init
  local ngx = ngx


  function Connector:store_connection(conn)
    if not past_init and ngx and ngx.get_phase() ~= "init" then
      past_init = true
    end

    if ngx and past_init then
      ngx.ctx.connection = conn

    else
      self.connection = conn
    end
  end


  function Connector:get_stored_connection()
    if not past_init and ngx and ngx.get_phase() ~= "init" then
      past_init = true
    end

    if ngx and past_init then
      return ngx.ctx.connection
    end

    return self.connection
  end
end


function Connector:infos()
  error(fmt("infos() not implemented for '%s' strategy", self.database))
end


function Connector:connect()
  error(fmt("connect() not implemented for '%s' strategy", self.database))
end


function Connector:connect_migrations()
  error(fmt("connect_migrations() not implemented for '%s' strategy",
            self.database))
end


function Connector:setkeepalive()
  error(fmt("setkeepalive() not implemented for '%s' strategy", self.database))
end


function Connector:close()
  error(fmt("close() not implemented for '%s' strategy", self.database))
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


function Connector:schema_migrations()
  error(fmt("schema_migrations() not implemented for '%s' strategy",
            self.database))
end


function Connector:schema_bootstrap()
  error(fmt("schema_bootstrap() not implemented for '%s' strategy",
            self.database))
end


function Connector:schema_reset()
  error(fmt("schema_reset() not implemented for '%s' strategy",
            self.database))
end


function Connector:run_up_migration()
  error(fmt("run_up_migration() not implemented for '%s' strategy",
            self.database))
end


function Connector:run_api_migrations()
  error(fmt("run_api_migrations() not implemented for '%s' strategy",
            self.database))
end


function Connector:wait_for_schema_consensus()
  return true
end


function Connector:record_migration()
  error(fmt("record_migration() not implemented for '%s' strategy",
            self.database))
end


return Connector
