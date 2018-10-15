local vitals = require "kong.vitals"
local utils  = require "kong.tools.utils"
local rl = require "kong.tools.public.rate-limiting"


local _M = {}


_M.EE_MODELS = {
  "token_statuses",
  "portal_reset_secrets",
}


function _M.additional_tables(dao)
  local additional_tables = {}

  for _, v in ipairs(vitals.table_names(dao)) do
    table.insert(additional_tables, v)
  end

  for _, v in ipairs(rl.table_names()) do
    table.insert(additional_tables, v)
  end

  return additional_tables
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
