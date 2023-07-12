local arrays = require "pgmoon.arrays"

local ipairs = ipairs
local encode_array  = arrays.encode_array
local migrate_path = require "kong.db.migrations.migrate_path_280_300"


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
}
