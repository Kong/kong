local dummy = function() return true end


local mutex_opts = {
  ttl = 10,
  no_wait = true,
}


return setmetatable({
  cluster = {
    keyring_add = function(id, local_only)
      if local_only then
        return true
      end

      local _, err = kong.db.keyring_meta:insert({
        id = id,
        state = "alive",
      })
      if err then
        return false, err
      end

      return true
    end,

    keyring_remove = function(id, quiet)
      if quiet then
        return true
      end

      local _, err = kong.db.keyring_meta:delete({ id = id })
      if err then
        return false, err
      end

      local ok, err = kong.cluster_events:broadcast("keyring_remove", id)
      if not ok then
        return false, err
      end

      return true
    end,

    activate = function(id)
      return kong.db:cluster_mutex("keyring_activate", mutex_opts, function()
        return kong.db.keyring_meta:activate(id)
      end)
    end,
  },
}, {
  __index = function()
    return setmetatable({}, { __index = function() return dummy end })
  end,
})
