local utils = require "kong.tools.utils"

local _M = {}

function _M.new_db(name)
  local db_mt                 = {
    name                      = name,
    init                      = function() return true end,
    init_worker               = function() return true end,
    infos                     = function() error('infos() not implemented') end,
    query                     = function() error('query() not implemented') end,
    insert                    = function() error('insert() not implemented') end,
    find                      = function() error('find() not implemented') end,
    find_all                  = function() error('find_all() not implemented') end,
    count                     = function() error('count() not implemented') end,
    update                    = function() error('update() not implemented') end,
    delete                    = function() error('delete() not implemented') end,
    queries                   = function() error('queries() not implemented') end,
    drop_table                = function() error('drop_table() not implemented') end,
    truncate_table            = function() error('truncate_table() not implemented') end,
    current_migrations        = function() error('current_migrations() not implemented') end,
    record_migration          = function() error('record_migration() not implemented') end,
    check_schema_consensus    = function() error("check_schema_consensus() not implemented") end,
    wait_for_schema_consensus = function() error("wait_for_schema_consensus() not implemented") end,
    clone_query_options       = function(self, options)
      options                 = options or {}
      local opts              = utils.shallow_copy(self.query_options)
      for k, v in pairs(options) do
        opts[k] = v
      end
      return opts
    end
  }

  db_mt.__index = db_mt

  db_mt.super = {
    new = function()
      return setmetatable({}, db_mt)
    end
  }

  return setmetatable(db_mt, {__index = db_mt.super})
end

return _M
