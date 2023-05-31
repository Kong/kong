local _M = {}


function _M.rt_rename(_, _, dao)
  local plugins, err = dao.plugins:find_all(
                       { name = "request-transformer-advanced" })
  if err then
    return err
  end

  local cycle_aware_cache = {}

  for i = 1, #plugins do
    local plugin = plugins[i]
    local _, err = dao.plugins:insert({
      name = "request-transformer",
      api_id = plugin.api_id,
      consumer_id = plugin.consumer_id,
      enabled = plugin.enabled,
      config = kong.table.deepclone(plugin.config, cycle_aware_cache),
    })
    if err then
      return err
    end

    -- drop the old entry
    local _, err = dao.plugins:delete(plugin, { quite = true })
    if err then
      return err
    end
  end
end


return _M
