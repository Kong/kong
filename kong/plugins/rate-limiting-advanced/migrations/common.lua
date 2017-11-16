local _M = {}


function _M.ee_rename(_, _, dao)
  local plugins, err = dao.plugins:find_all({ name = "rate-limiting" })
  if err then
    return err
  end

  for i = 1, #plugins do
    -- look for something that looks like the ee plugin
    local plugin = plugins[i]

    local is_ee = false
    do
      local c = plugin.config
      if c.namespace   and
         c.identifier  and
         c.window_size and
         c.limit       and
         c.sync_rate   and
         c.strategy    then

        is_ee = true
     end
    end

    if is_ee then
      plugin.config.window_type = "sliding"

      local _, err = dao.plugins:insert({
        name = "rate-limiting-advanced",
        api_id = plugin.api_id,
        consumer_id = plugin.consumer_id,
        enabled = plugin.enabled,
        config = plugin.config,
      })
      if err then
        return err
      end
    end

    -- drop the old entry
    local _, err = dao.plugins:delete(plugin, { quiet = true })
    if err then
      return err
    end
  end
end


return _M
