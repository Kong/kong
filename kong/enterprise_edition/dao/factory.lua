local pl_tablex = require "pl.tablex"
local utils  = require "kong.tools.utils"
local rl = require "kong.tools.public.rate-limiting"
local vitals = require "kong.vitals"


local _M = {}


local function additional_tables(dao)
  return pl_tablex.merge(vitals.table_names(dao), rl.table_names(), true)
end

_M.additional_tables = additional_tables


local function merge_enterprise_migrations(ce_migrations, db, migrations_type)
  local ok, m = utils.load_module_if_exists("kong.enterprise_edition.dao.migrations." ..
                                            migrations_type .. "." .. db)
  if ok then
    for i, migration in ipairs(m) do
      table.insert(ce_migrations[migrations_type], migration)
    end
  end


  return
end
_M.merge_enterprise_migrations = merge_enterprise_migrations


return _M
