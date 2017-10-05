local json_decode = require("cjson.safe").decode


local _M = {}


-- Iterator to update plugin configurations.
-- It works indepedent of the underlying datastore.
-- @param dao the dao to use
-- @param plugin_name the name of the plugin whos configurations
-- to iterate over
-- @return `ok+config+update` where `ok` is a boolean, `config` is the plugin configuration
-- table (or the error if not ok), and `update` is an update function to call with
-- the updated configuration table
-- @usage
--    up = function(_, _, dao)
--      for ok, config, update in plugin_config_iterator(dao, "jwt") do
--        if not ok then
--          return config
--        end
--        if config.run_on_preflight == nil then
--          config.run_on_preflight = true
--          local _, err = update(config)
--          if err then
--            return err
--          end
--        end
--      end
--    end
function _M.plugin_config_iterator(dao, plugin_name)

  -- iterates over rows
  local run_rows = function(t)
    for _, row in ipairs(t) do
      if type(row.config) == "string" then
        -- de-serialize in case of Cassandra
        local json, err = json_decode(row.config)
        if not json then
          return nil, ("json decoding error '%s' while decoding '%s'"):format( 
                      tostring(err), tostring(row.config))
        end
        row.config = json
      end
      coroutine.yield(row.config, function(updated_config)
        if type(updated_config) ~= "table" then
          return nil, "expected table, got " .. type(updated_config)
        end
        row.created_at = nil
        row.config = updated_config
        return dao.plugins:update(row, {id = row.id})
      end)
    end
    return true
  end

  local coro
  if dao.db_type == "cassandra" then
    coro = coroutine.create(function()
      local coordinator = dao.db:get_coordinator()
      for rows, err in coordinator:iterate([[
                SELECT * FROM plugins WHERE name = ']] .. plugin_name .. [[';
              ]]) do
        if err then
          return nil, nil, err
        end

        assert(run_rows(rows))
      end
    end)

  elseif dao.db_type == "postgres" then
    coro = coroutine.create(function()
      local rows, err = dao.db:query([[
        SELECT * FROM plugins WHERE name = ']] .. plugin_name .. [[';
      ]])
      if err then
        return nil, nil, err
      end

      assert(run_rows(rows))
    end)

  else
    coro = coroutine.create(function()
      return nil, nil, "unknown database type: " .. tostring(dao.db_type)
    end)
  end

  return function()
    local coro_ok, config, update, err = coroutine.resume(coro)
    if not coro_ok then return false, config end  -- coroutine errored out
    if err         then return false, err    end  -- dao soft error
    if not config  then return nil           end  -- iterator done
    return true, config, update
  end
end


return _M
