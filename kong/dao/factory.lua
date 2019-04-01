local DAO = require "kong.dao.dao"
local log = require "kong.cmd.utils.log"
local utils = require "kong.tools.utils"
local version = require "version"
local constants = require "kong.constants"
local ModelFactory = require "kong.dao.model_factory"
local ee_dao_factory = require "kong.enterprise_edition.dao.factory"
local workspaces = require "kong.workspaces"
local rbac_migrations_admins = require "kong.rbac.migrations.02_admins"
local rbac_migrations_basic_auth = require "kong.rbac.migrations.04_kong_admin_basic_auth"


local fmt = string.format

local CORE_MODELS = {
  "apis",
  "credentials",
  -- "consumers_rbac_users_map",
  "audit_requests",
  "audit_objects",
}

-- returns db errors as strings, including the initial `nil`
local function ret_error_string(db_name, res, err)
  res, err = DAO.ret_error(db_name, res, err)
  return res, tostring(err)
end

local _M = {}

function _M:__index(key)
  local daos = rawget(self, "daos")
  if daos and daos[key] then
    return daos[key]
  else
    return _M[key]
  end
end

local function build_constraints(schemas)
  local all_constraints = {}
  for m_name, schema in pairs(schemas) do
    local constraints = {foreign = {}, unique = {}}
    for col, field in pairs(schema.fields) do
      if type(field.foreign) == "string" then
        local f_entity, f_field = unpack(utils.split(field.foreign, ":"))
        if f_entity ~= nil and f_field ~= nil then
          local f_schema = schemas[f_entity]
          constraints.foreign[col] = {
            table = f_schema and f_schema.table or f_entity,
            schema = f_schema,
            col = f_field,
            f_entity = f_entity
          }
        end
      end
      if field.unique then
        constraints.unique[col] = {
          table = schema.table,
          schema = schema
        }
      end
    end
    all_constraints[m_name] = constraints
  end

  return all_constraints
end

local function load_daos(self, schemas, constraints, new_db)
  for m_name, schema in pairs(schemas) do
    if constraints[m_name] ~= nil and constraints[m_name].foreign ~= nil then
      for col, f_constraint in pairs(constraints[m_name].foreign) do
        local parent_name = f_constraint.f_entity

        -- New-DAO parents may not have a `constraints` entry yet
        if not constraints[parent_name] then
          constraints[parent_name] = {}
        end

        local parent_constraints = constraints[parent_name]
        if parent_constraints.cascade == nil then
          parent_constraints.cascade = {}
        end

        parent_constraints.cascade[m_name] = {
          table = schema.table,
          schema = schema,
          f_col = col,
          col = f_constraint.col
        }
      end
    end
  end

  -- Hardcode cascade-delete constraint between `apis` and `plugins`.
  -- This is the only old-DAO to new-DAO constraint,
  -- once `apis` becomes the last old-DAO entity.
  local constraints_apis = constraints["apis"]
  constraints_apis.cascade = constraints_apis.cascade or {}
  constraints_apis.cascade["plugins"] = {
    new_db = true,
    db_entity = new_db.plugins,
    table = "plugins",
    f_col = "api",
  }

  for m_name, schema in pairs(schemas) do
    self.daos[m_name] = DAO(self.db, ModelFactory(schema), schema,
                            constraints[m_name])

    if schema.workspaceable then
      workspaces.register_workspaceable_relation(m_name, schema.primary_key,
                                                 constraints[m_name] and
                                                 constraints[m_name].unique)
    end
  end
end


local function create_legacy_wrappers(self, constraints)
  local new_db = self.db.new_db
  local dao_wrappers = {}
  for name, new_dao in pairs(new_db.daos) do
    if new_dao.schema.legacy then
      goto continue
    end

    dao_wrappers[name] = {

      constraints = constraints[name],

      unwrapped = new_dao,

      cache_key = function(_, a1, a2, a3, a4, a5)
        return new_dao:cache_key(a1, a2, a3, a4, a5)
      end,

      entity_cache_key = function(_, entity)
        log.debug(debug.traceback("[legacy wrapper] using legacy wrapper"))
        return new_dao:cache_key(entity)
      end,

      insert = function(_, tbl, opts)
        log.debug(debug.traceback("[legacy wrapper] using legacy wrapper"))
        if opts then
          if opts.quiet then
            log.warn("[legacy wrapper] quiet is ignored, event always sent")
          end
        end
        local ok, _, err_t = new_dao:insert(tbl, { ttl = opts and opts.ttl })
        if not ok then
          return ok, err_t
        end
        return ok
      end,

      find = function(_, args)
        log.debug(debug.traceback("[legacy wrapper] using legacy wrapper"))
        local pk = new_dao.schema:extract_pk_values(args)
        local row, _, err_t = new_dao:select(pk)
        if not row then
          return row, err_t
        end
        return row
      end,

      find_all = function(_, filt)

        filt = filt or {}
        filt.__skip_rbac = nil -- remove skip_rbac from here

        local rows = {}
        local filtering = false
        if filt and next(filt) then
          filtering = true
        end
        for row, err in new_dao:each(nil, {skip_rbac = filt.__skip_rbac}) do
          if err then
            return nil, err
          end
          if filtering then
            local match = true
            for k,v in pairs(filt) do
              local foreign = k:match("^(.*)_id$")
              if foreign then
                if (row[foreign] == ngx.null and v ~= ngx.null)
                or (row[foreign].id ~= v) then
                  goto continue
                end
              else
                if row[k] ~= v and not string.find(tostring(row[k]), "^.*:" .. tostring(v)) then
                  goto continue
                end
              end
            end
            if match then
              rows[#rows + 1] = row
            end
          else
            rows[#rows + 1] = row
          end
          ::continue::
        end
        log.debug(debug.traceback("[legacy wrapper] using legacy wrapper"))
        return rows
      end,

      count = function(self, filt)
        log.debug(debug.traceback("[legacy wrapper] using legacy wrapper"))
        local rows, err, err_t = self:find_all(filt)
        if err then
          return nil, err_t
        end
        return #rows
      end,

      find_page = function(_, tbl, page_offset, page_size)
        log.debug(debug.traceback("[legacy wrapper] using legacy wrapper"))
        if tbl and next(tbl) then
          return nil, "[legacy wrapper] filtering is not supported"
        end
        return new_dao:page(page_size, page_offset)
      end,

      update = function(_, tbl, filter_keys, opts)
        log.debug(debug.traceback("[legacy wrapper] using legacy wrapper"))
        if opts then
          if opts.full then
            log.warn("[legacy wrapper] full is ignored")
          end
          if opts.quiet then
            log.warn("[legacy wrapper] quiet is ignored, event always sent")
          end
        end
        local pk = new_dao.schema:extract_pk_values(filter_keys)
        local ok, _, err_t = new_dao:update(pk, tbl)
        if not ok then
          return ok, err_t
        end
        return ok
      end,

      delete = function(_, tbl, opts)
        log.debug(debug.traceback("[legacy wrapper] using legacy wrapper"))
        if opts then
          if opts.quiet then
            log.warn("[legacy wrapper] quiet is ignored, event always sent")
          end
        end
        local ok, _, err_t = new_dao:delete(tbl)
        if not ok then
          return ok, err_t
        end
        return ok
      end,

      truncate = function(_)
        log.debug(debug.traceback("[legacy wrapper] using legacy wrapper"))
        return new_dao:truncate()
      end,
    }

    ::continue::
  end

  -- Make wrappers accessible by keying daos, but do not return
  -- them when iterating self.daos with pairs()
  setmetatable(self.daos, { __index = dao_wrappers })
end


function _M.new(kong_config, new_db)
  local self = {
    db_type = kong_config.database,
    daos = {},
    additional_tables = {},
    kong_config = kong_config,
    plugin_names = kong_config.loaded_plugins or {}
  }

  local DB = require("kong.dao.db." .. self.db_type)
  local db, err = DB.new(kong_config)
  if not db then
    return ret_error_string(self.db_type, nil, err)
  end

  db.new_db = new_db
  self.db = db

  local schemas = {}
  for _, m_name in ipairs(CORE_MODELS) do
    schemas[m_name] = require("kong.dao.schemas." .. m_name)
  end

  for plugin_name in pairs(self.plugin_names) do
    local has_schema, plugin_schemas = utils.load_module_if_exists("kong.plugins." .. plugin_name .. ".daos")
    if has_schema then
      if plugin_schemas.tables then
        for _, v in ipairs(plugin_schemas.tables) do
          table.insert(self.additional_tables, v)
        end
      else
        for k, v in pairs(plugin_schemas) do
          if not v.name then
            schemas[k] = v
          end
        end
      end
    end
  end

  local constraints = build_constraints(schemas)
  load_daos(self, schemas, constraints, new_db)

  create_legacy_wrappers(self, constraints)

  return setmetatable(self, _M)
end

function _M:check_version_compat(min, deprecated)
  local db_infos = self:infos()
  if db_infos.version == "unknown" then
    return nil, "could not check database compatibility: version " ..
                "is unknown (did you call ':init'?)"
  end

  local db_v = version.version(db_infos.version)
  local min_v = version.version(min)

  if db_v < min_v then
    if deprecated then
      local depr_v = version.version(deprecated)

      if db_v >= depr_v then
        log.warn("Currently using %s %s which is considered deprecated, " ..
                 "please use %s or greater", db_infos.db_name,
                 db_infos.version, min)

        return true
      end
    end

    return nil, fmt("Kong requires %s %s or greater (currently using %s)",
                    db_infos.db_name, min, db_infos.version)
  end

  return true
end

function _M:init()
  local ok, err = self.db:init()
  if not ok then
    return ret_error_string(self.db_type, nil, err)
  end

  local db_constants = constants.DATABASE[self.db_type:upper()]

  ok, err = self:check_version_compat(db_constants.MIN, db_constants.DEPRECATED)
  if not ok then
    return ret_error_string(self.db_type, nil, err)
  end

  return true
end

function _M:init_worker()
  return self.db:init_worker()
end

function _M:set_events_handler(events)
  for _, dao in pairs(self.daos) do
    dao.events = events
  end
end

-- Migrations

function _M:infos()
  return self.db:infos()
end

function _M:drop_schema()
  for _, dao in pairs(self.daos) do
    self.db:drop_table(dao.table)
  end

  if self.additional_tables then
    for _, v in ipairs(self.additional_tables) do
      self.db:drop_table(v)
    end
  end

  if self.db.additional_tables then
    for _, v in ipairs(self.db.additional_tables) do
      self.db:drop_table(v)
    end
  end

  if ee_dao_factory.additional_tables then
    for _, v in ipairs(ee_dao_factory.additional_tables(self)) do
      self.db:drop_table(v)
    end
  end

  self.db:drop_table("schema_migrations")
end

function _M:truncate_table(dao_name)
  self.db:truncate_table(self.daos[dao_name].table)

  -- If we are truncating workspaces, re-create the default workspace
  if dao_name == "workspaces" then
    workspaces.upsert_default()
  end

  local is_workspaceable = workspaces.get_workspaceable_relations()[dao_name]

  if is_workspaceable then
    local res, _ = workspaces.compat_find_all("workspace_entities", {entity_type = dao_name})
    for _, v in ipairs(res) do
      workspaces.delete_entity_relation("workspace_entities", {
        workspace_id = v.workspace_id,
        entity_id = v.entity_id,
        unique_field_name = v.unique_field_name,
      })
    end
  end
end

function _M:truncate_tables()
  for _, dao in pairs(self.daos) do
    if dao.table then
      self.db:truncate_table(dao.table)
    end
  end

  if self.db.additional_tables then
    for _, v in ipairs(self.db.additional_tables) do
      self.db:truncate_table(v)
    end
  end

  if self.additional_tables then
    for _, v in ipairs(self.additional_tables) do
      self.db:truncate_table(v)
    end
  end

  if ee_dao_factory.additional_tables then
    for _, v in ipairs(ee_dao_factory.additional_tables(self)) do
      self.db:truncate_table(v)
    end
  end

  -- If we are truncating workspaces, re-create the default workspace
  workspaces.upsert_default()
end

function _M:migrations_modules()
  local migrations = {
    core = utils.deep_copy(require("kong.dao.migrations." .. self.db_type))
  }

  ee_dao_factory.merge_enterprise_migrations(migrations, self.db_type, "core")

  for plugin_name in pairs(self.plugin_names) do
    local ok, plugin_mig = utils.load_module_if_exists("kong.plugins." .. plugin_name .. ".migrations." .. self.db_type)
    if ok then
      migrations[plugin_name] = utils.deep_copy(plugin_mig)
    end

    ee_dao_factory.merge_enterprise_migrations(migrations, self.db_type,
                                               plugin_name)
  end

  do
    -- check that migrations have a name, and that no two migrations have the
    -- same name.
    local migration_names = {}

    for plugin_name, plugin_migrations in pairs(migrations) do
      for i, migration in ipairs(plugin_migrations) do
        local s = plugin_name == "core" and
                    "'core'" or "plugin '" .. plugin_name .. "'"

        if migration.name == nil then
          return nil, string.format("migration '%d' for %s has no " ..
                                    "name", i, s)
        end

        if type(migration.name) ~= "string" then
          return nil, string.format("migration '%d' for %s must be a string",
                                    i, s)
        end

        if migration_names[migration.name] then
          return nil, string.format("migration '%s' (%s) already " ..
                                    "exists; migrations must have unique names",
                                    migration.name, s)
        end

        migration_names[migration.name] = true
      end
    end
  end

  return migrations
end

function _M:current_migrations()
  local rows, err = self.db:current_migrations()
  if err then
    return ret_error_string(self.db.name, nil, err)
  end

  local cur_migrations = {}
  for _, row in ipairs(rows) do
    cur_migrations[row.id] = row.migrations
  end
  return cur_migrations
end

local function migrate(self, identifier, migrations_modules, cur_migrations, on_migrate, on_success)
  local migrations = migrations_modules[identifier]
  local recorded = {}
  for _, name in ipairs(cur_migrations[identifier] or {}) do
    recorded[name] = true
  end

  local to_run = {}
  for _, mig in ipairs(migrations) do
    if not recorded[mig.name] then
      to_run[#to_run + 1] = mig
    end
  end

  if #to_run > 0 and on_migrate then
    -- we have some migrations to run
    on_migrate(identifier, self.db:infos())
  end

  for _, migration in ipairs(to_run) do
    local err
    local mig_type = type(migration.up)
    if mig_type == "string" then
      err = self.db:queries(migration.up)
    elseif mig_type == "function" then
      err = migration.up(self.db, self.kong_config, self)
    end

    if err and migration.ignore_error then
      if type(migration.ignore_error) == "boolean" or
         (type(migration.ignore_error) == "string" and
          string.find(tostring(err), migration.ignore_error, 1, true)) then
        err = nil
      end
    end

    if err then
      return nil, string.format("Error during migration %s: %s", migration.name, err)
    end

    -- record success
    local ok, err = self.db:record_migration(identifier, migration.name)
    if not ok then
      return nil, string.format("Error recording migration %s: %s", migration.name, err)
    end

    if on_success then
      on_success(identifier, migration.name, self.db:infos())
    end
  end

  return true, nil, #to_run
end

local function default_on_migrate(identifier, db_infos)
  log("migrating %s for %s %s",
      identifier, db_infos.desc, db_infos.name)
end

local function default_on_success(identifier, migration_name, db_infos)
  log("%s migrated up to: %s",
      identifier, migration_name)
end

function _M:are_migrations_uptodate()
  local migrations_modules, err = self:migrations_modules()
  if not migrations_modules then
    return ret_error_string(self.db.name, nil, err)
  end

  local cur_migrations, err = self:current_migrations()
  if err then
    return ret_error_string(self.db.name, nil,
                            "could not retrieve current migrations: " .. err)
  end

  for module, migrations in pairs(migrations_modules) do
    for _, migration in ipairs(migrations) do
      if not (cur_migrations[module] and
              utils.table_contains(cur_migrations[module], migration.name))
      then
        local infos = self.db:infos()
        log.warn("%s %s '%s' is missing migration: (%s) %s",
                 self.db_type, infos.desc, infos.name, module, migration.name or "(no name)")
        return ret_error_string(self.db.name, nil, "the current database "   ..
                                "schema does not match this version of "     ..
                                "Kong. Please run `kong migrations up` "     ..
                                "to update/initialize the database schema. " ..
                                "Be aware that Kong migrations should only " ..
                                "run from a single node, and that nodes "    ..
                                "running migrations concurrently will "      ..
                                "conflict with each other and might "        ..
                                "corrupt your database schema!")
      end
    end
  end

  return true
end

function _M:check_schema_consensus()
  if self.db.name ~= "cassandra" then
    return true -- only applicable for cassandra
  end

  log.verbose("checking Cassandra schema consensus...")

  local ok, err = self.db:check_schema_consensus()
  if err then
    return ret_error_string(self.db.name, nil,
                            "failed to check for schema consensus: " .. err)
  end

  log.verbose("Cassandra schema consensus: %s",
              ok ~= nil and "reached" or "not reached")

  return ok
end

function _M:run_migrations(on_migrate, on_success)
  on_migrate = on_migrate or default_on_migrate
  on_success = on_success or default_on_success

  log.verbose("running datastore migrations")

  if self.db.name == "cassandra" then
    local ok, err = self.db:first_coordinator()
    if not ok then
      return ret_error_string(self.db.name, nil,
                              "could not find coordinator: " .. err)
    end
  end

  local migrations_modules, err = self:migrations_modules()
  if not migrations_modules then
    return ret_error_string(self.db.name, nil, err)
  end

  local cur_migrations, err = self:current_migrations()
  if err then
    return ret_error_string(self.db.name, nil,
                            "could not retrieve current migrations: " .. err)
  end

  local ok, err, migrations_ran = migrate(self, "core", migrations_modules, cur_migrations, on_migrate, on_success)
  if not ok then
    return ret_error_string(self.db.name, nil, err)
  end

  for identifier in pairs(migrations_modules) do
    if identifier ~= "core" then
      local ok, err, n_ran = migrate(self, identifier, migrations_modules, cur_migrations, on_migrate, on_success)
      if not ok then return ret_error_string(self.db.name, nil, err)
      else
        migrations_ran = migrations_ran + n_ran
      end
    end
  end

  -- this migration must happen after plugin migrations, before workspace one
  local _, err, n_ran = migrate(self, "admins", rbac_migrations_admins,
    cur_migrations, on_migrate, on_success)
  if err then
    return ret_error_string(self.db.name, nil, err)
  end
  migrations_ran = migrations_ran + n_ran

  -- run workspace-related migrations
  local def_workspace_migration = workspaces.get_default_workspace_migration()
  local _, err, n_ran = migrate(self, "default_workspace", def_workspace_migration,
    cur_migrations, on_migrate, on_success)
  if err then
    return ret_error_string(self.db.name, nil, err)
  end
  migrations_ran = migrations_ran + n_ran

  -- this migration must happen after plugin migrations
  local _, err, n_ran = migrate(self, "kong_admin_basic_auth", rbac_migrations_basic_auth,
    cur_migrations, on_migrate, on_success)
  if err then
    return ret_error_string(self.db.name, nil, err)
  end
  migrations_ran = migrations_ran + n_ran

  -- create entity counters per workspace
  local workspace_entity_counters_migration = workspaces.get_initialize_workspace_entity_counters_migration()
  local _, err, n_ran = migrate(self,
    "workspace_counters",
    workspace_entity_counters_migration,
    cur_migrations, on_migrate, on_success)
  if err then
    return ret_error_string(self.db.name, nil, err)
  end
  migrations_ran = migrations_ran + n_ran

  if migrations_ran > 0 then
    log("%d migrations ran", migrations_ran)

    if self.db.name == "cassandra" then
      log("waiting for Cassandra schema consensus (%dms timeout)...",
          self.db.cluster.max_schema_consensus_wait)

      local ok, err = self.db:wait_for_schema_consensus()
      if not ok then
        return ret_error_string(self.db.name, nil,
                                "failed to wait for schema consensus: " .. err)
      end

      log("Cassandra schema consensus: reached")
    end
  end

  if self.db.name == "cassandra" then
    local ok, err = self.db:close_coordinator()
    if not ok then
      return ret_error_string(self.db.name, nil,
                              "could not close coordinator: " .. err)
    end
  end

  log.verbose("migrations up to date")

  return true
end

return _M
