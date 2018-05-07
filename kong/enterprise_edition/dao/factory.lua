local pl_tablex = require "pl.tablex"
local vitals = require "kong.vitals"
local utils  = require "kong.tools.utils"
local rl = require "kong.tools.public.rate-limiting"


local _M = {}


function _M.additional_tables(dao)
  return pl_tablex.merge(vitals.table_names(dao), rl.table_names(), true)
end


function _M.merge_enterprise_migrations(ce_migrations, db, migrations_type)
  local module_prefix = "kong.enterprise_edition.dao.migrations."
  local module_path = module_prefix .. migrations_type .. "." .. db

  local ok, m = utils.load_module_if_exists(module_path)
  if ok then
    for i, migration in ipairs(m) do
      table.insert(ce_migrations[migrations_type], migration)
    end
  end

  return
end


return _M
