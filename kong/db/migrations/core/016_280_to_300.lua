local log = require "kong.cmd.utils.log"
local arrays = require "pgmoon.arrays"

local fmt = string.format
local assert = assert
local ipairs = ipairs
local cassandra = require "cassandra"
local encode_array  = arrays.encode_array
local migrate_path = require "kong.db.migrations.migrate_path_280_300"


-- remove repeated targets, the older ones are not useful anymore. targets with
-- weight 0 will be kept, as we cannot tell which were deleted and which were
-- explicitly set as 0.
local function c_remove_unused_targets(coordinator)
  local upstream_targets = {}
  for rows, err in coordinator:iterate("SELECT id, upstream_id, target, created_at FROM targets") do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      local key = fmt("%s:%s", row.upstream_id, row.target)

      if not upstream_targets[key] then
        upstream_targets[key] = {
          id = row.id,
          created_at = row.created_at,
        }
      else
        local to_remove
        if row.created_at > upstream_targets[key].created_at then
          to_remove = upstream_targets[key].id
          upstream_targets[key] = {
            id = row.id,
            created_at = row.created_at,
          }
        else
          to_remove = row.id
        end
        local _, err = coordinator:execute("DELETE FROM targets WHERE id = ?", {
          cassandra.uuid(to_remove)
        })

        if err then
          return nil, err
        end
      end
    end
  end

  return true
end


-- update cache_key for targets
local function c_update_target_cache_key(coordinator)
  for rows, err in coordinator:iterate("SELECT id, upstream_id, target, ws_id FROM targets") do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      local cache_key = fmt("targets:%s:%s::::%s", row.upstream_id, row.target, row.ws_id)

      local _, err = coordinator:execute("UPDATE targets SET cache_key = ? WHERE id = ? IF EXISTS", {
        cache_key, cassandra.uuid(row.id)
      })

      if err then
        return nil, err
      end
    end
  end

  return true
end


local function c_copy_vaults_to_vault_auth_vaults(coordinator)
  for rows, err in coordinator:iterate("SELECT id, created_at, updated_at, name, protocol, host, port, mount, vault_token FROM vaults") do
    if err then
      log.warn("ignored error while running '016_280_to_300' migration: " .. err)
      return true
    end

    for _, row in ipairs(rows) do
      local _, err = coordinator:execute(
        "INSERT INTO vault_auth_vaults (id, created_at, updated_at, name, protocol, host, port, mount, vault_token) " ..
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        {
          cassandra.uuid(row.id),
          cassandra.timestamp(row.created_at),
          cassandra.timestamp(row.updated_at),
          cassandra.text(row.name),
          cassandra.text(row.protocol),
          cassandra.text(row.host),
          cassandra.int(row.port),
          cassandra.text(row.mount),
          cassandra.text(row.vault_token)
        }
      )
      if err then
        return nil, err
      end
    end
  end

  return true
end


local function c_copy_vaults_beta_to_sm_vaults(coordinator)
  for rows, err in coordinator:iterate("SELECT id, ws_id, prefix, name, description, config, created_at, updated_at, tags FROM vaults_beta") do
    if err then
      log.warn("ignored error while running '016_280_to_300' migration: " .. err)
      return true
    end

    for _, row in ipairs(rows) do
      local _, err = coordinator:execute(
        "INSERT INTO sm_vaults (id, ws_id, prefix, name, description, config, created_at, updated_at, tags) " ..
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        {
          cassandra.uuid(row.id),
          cassandra.uuid(row.ws_id),
          cassandra.text(row.prefix),
          cassandra.text(row.name),
          cassandra.text(row.description),
          cassandra.text(row.config),
          cassandra.timestamp(row.created_at),
          cassandra.timestamp(row.updated_at),
          cassandra.set(row.tags)
        }
      )
      if err then
        return nil, err
      end
    end
  end

  return true
end


local function c_migrate_regex_path(coordinator)
  for rows, err in coordinator:iterate("SELECT id, paths FROM routes") do
    if err then
      return nil, err
    end

    for i = 1, #rows do
      local route = rows[i]

      if not route.paths then
        goto continue
      end

      local changed = false
      for idx, path in ipairs(route.paths) do
        local normalized_path, current_changed = migrate_path(path)
        if current_changed then
          changed = true
          route.paths[idx] = normalized_path
        end
      end

      if changed then
        local _, err = coordinator:execute(
          "UPDATE routes SET paths = ? WHERE partition = 'routes' AND id = ?",
          { cassandra.list(route.paths), cassandra.uuid(route.id) }
        )
        if err then
          return nil, err
        end
      end
      ::continue::
    end
  end
  return true
end

local function render(template, keys)
  return (template:gsub("$%(([A-Z_]+)%)", keys))
end

local function p_migrate_regex_path(connector)
  for route, err in connector:iterate("SELECT id, paths FROM routes WHERE paths IS NOT NULL") do
    if err then
      return nil, err
    end

    local changed = false
    for idx, path in ipairs(route.paths) do
      local normalized_path, current_changed = migrate_path(path)
      if current_changed then
        changed = true
        route.paths[idx] = normalized_path
      end
    end

    if changed then
      local sql = render(
        "UPDATE routes SET paths = $(NORMALIZED_PATH) WHERE id = '$(ID)'", {
        NORMALIZED_PATH = encode_array(route.paths),
        ID = route.id,
      })

      local _, err = connector:query(sql)
      if err then
        return nil, err
      end
    end
  end

  return true
end

local function p_update_cache_key(connector)
  local _, err = connector:query([[
    DELETE FROM targets t1
          USING targets t2
          WHERE t1.created_at < t2.created_at
            AND t1.upstream_id = t2.upstream_id
            AND t1.target = t2.target;
    UPDATE targets SET cache_key = CONCAT('targets:', upstream_id, ':', target, '::::', ws_id);
    ]])

  if err then
    return nil, err
  end

  return true
end

return {
  postgres = {
    up = [[
      DO $$
        BEGIN
          IF (SELECT to_regclass('vaults_beta')) IS NOT NULL AND (SELECT to_regclass('sm_vaults')) IS NULL THEN
            CREATE TABLE sm_vaults ( LIKE vaults_beta INCLUDING ALL );

            CREATE TRIGGER "sm_vaults_sync_tags_trigger"
            AFTER INSERT OR UPDATE OF tags OR DELETE ON sm_vaults
            FOR EACH ROW
            EXECUTE PROCEDURE sync_tags();

            ALTER TABLE sm_vaults ADD CONSTRAINT sm_vaults_ws_id_fkey FOREIGN KEY(ws_id) REFERENCES workspaces(id);

            INSERT INTO sm_vaults SELECT * FROM vaults_beta;
          END IF;

          IF (SELECT to_regclass('vaults')) IS NOT NULL AND (SELECT to_regclass('vault_auth_vaults')) IS NULL THEN
            CREATE TABLE vault_auth_vaults ( LIKE vaults INCLUDING ALL );

            INSERT INTO vault_auth_vaults SELECT * FROM vaults;
          END IF;
        END;
      $$;

      DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "targets" ADD COLUMN "cache_key" TEXT UNIQUE;
        EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
        END;
      $$;

      -- add new hash_on_query_arg field to upstreams
      DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "upstreams" ADD "hash_on_query_arg" TEXT;
        EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
        END;
      $$;

      -- add new hash_fallback_query_arg field to upstreams
      DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "upstreams" ADD "hash_fallback_query_arg" TEXT;
        EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
        END;
      $$;

      -- add new hash_on_uri_capture field to upstreams
      DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "upstreams" ADD "hash_on_uri_capture" TEXT;
        EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
        END;
      $$;

      -- add new hash_fallback_uri_capture field to upstreams
      DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "upstreams" ADD "hash_fallback_uri_capture" TEXT;
        EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
        END;
      $$;

      DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "routes" ADD COLUMN "expression" TEXT;
        EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
        END;
      $$;

      DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "routes" ADD COLUMN "priority" BIGINT;
        EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
        END;
      $$;
    ]],

    up_f = p_migrate_regex_path,

    teardown = function(connector)
      local _, err = connector:query([[
        DROP TABLE IF EXISTS vaults_beta;
        DROP TABLE IF EXISTS vaults;
        ]])

      if err then
        return nil, err
      end

      local _, err = p_update_cache_key(connector)
      if err then
        return nil, err
      end

      return true
    end
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS vault_auth_vaults (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        name        text,
        protocol    text,
        host        text,
        port        int,
        mount       text,
        vault_token text,
        PRIMARY KEY (id)
      );

      CREATE TABLE IF NOT EXISTS sm_vaults (

        id          uuid,
        ws_id       uuid,
        prefix      text,
        name        text,
        description text,
        config      text,
        created_at  timestamp,
        updated_at  timestamp,
        tags        set<text>,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS sm_vaults_prefix_idx ON sm_vaults (prefix);
      CREATE INDEX IF NOT EXISTS sm_vaults_ws_id_idx  ON sm_vaults (ws_id);

      ALTER TABLE targets ADD cache_key text;
      CREATE INDEX IF NOT EXISTS targets_cache_key_idx ON targets(cache_key);

      -- add new hash_on_query_arg field to upstreams
      ALTER TABLE upstreams ADD hash_on_query_arg text;

      -- add new hash_fallback_query_arg field to upstreams
      ALTER TABLE upstreams ADD hash_fallback_query_arg text;

      -- add new hash_on_uri_capture field to upstreams
      ALTER TABLE upstreams ADD hash_on_uri_capture text;

      -- add new hash_fallback_uri_capture field to upstreams
      ALTER TABLE upstreams ADD hash_fallback_uri_capture text;

      ALTER TABLE routes ADD expression text;
      ALTER TABLE routes ADD priority int;
    ]],

    up_f = function(connector)
      local coordinator = assert(connector:get_stored_connection())
      local _, err = c_copy_vaults_to_vault_auth_vaults(coordinator)
      if err then
        return nil, err
      end

      _, err = c_copy_vaults_beta_to_sm_vaults(coordinator)
      if err then
        return nil, err
      end

      _, err = c_migrate_regex_path(coordinator)
      if err then
        return nil, err
      end
    end,

    teardown = function(connector)

      local coordinator = assert(connector:get_stored_connection())
      local _, err = c_remove_unused_targets(coordinator)
      if err then
        return nil, err
      end

      _, err = c_update_target_cache_key(coordinator)
      if err then
        return nil, err
      end

      _, err = coordinator:execute("DROP TABLE IF EXISTS vaults_beta");
      if err then
        return nil, err
      end

      _, err = coordinator:execute("DROP TABLE IF EXISTS vaults");
      if err then
        return nil, err
      end

      local ok
      ok, err = connector:wait_for_schema_consensus()
      if not ok then
        return nil, err
      end

      return true
    end
  },
}
