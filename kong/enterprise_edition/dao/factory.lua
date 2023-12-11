-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local vitals = require "kong.vitals"
local rl = require "kong.tools.public.rate-limiting"
local load_module_if_exists = require "kong.tools.module".load_module_if_exists


local _M = {}


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

  local ok, m = load_module_if_exists(module_path)
  if ok then
    for i, migration in ipairs(m) do
      table.insert(ce_migrations[migrations_type], migration)
    end
  end

  return
end


return _M
