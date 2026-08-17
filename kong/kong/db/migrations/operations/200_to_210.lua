-- Helper module for 200_to_210 migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.


local uuid = require "resty.jit-uuid"


local default_ws_id = uuid.generate_v4()


local function render(template, keys)
  return (template:gsub("$%(([A-Z_]+)%)", keys))
end


--------------------------------------------------------------------------------
-- Postgres operations for Workspace migration
--------------------------------------------------------------------------------


local postgres = {

  up = {

    ----------------------------------------------------------------------------
    -- Add `workspaces` table.
    -- @return string: SQL
    ws_add_workspaces = function(_)
      return render([[

        CREATE TABLE IF NOT EXISTS "workspaces" (
          "id"         UUID                       PRIMARY KEY,
          "name"       TEXT                       UNIQUE,
          "comment"    TEXT,
          "created_at" TIMESTAMP WITH TIME ZONE   DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
          "meta"       JSONB,
          "config"     JSONB
        );

        -- Create default workspace
        INSERT INTO workspaces(id, name)
        VALUES ('$(ID)', 'default') ON CONFLICT DO NOTHING;

      ]], {
        ID = default_ws_id
      })
    end,

    ----------------------------------------------------------------------------
    -- Add `ws_id` field to a table.
    -- @param table_name string: name of the table, e.g. "services"
    -- @param fk_users {string:string}: map of tables and field names
    -- for other tables that use this table as a foreign key.
    -- We do NOT get these from the schemas because
    -- we want the migration to remain self-contained and unchanged no matter
    -- what changes to the schemas in the latest version of Kong.
    -- @return string: SQL
    ws_add_ws_id = function(_, table_name, fk_users)
      local out = {}
      table.insert(out, render([[

        -- Add ws_id to $(TABLE), populating all of them with the default workspace id
        DO $$
        BEGIN
          EXECUTE format('ALTER TABLE IF EXISTS ONLY "$(TABLE)" ADD "ws_id" UUID REFERENCES "workspaces" ("id") DEFAULT %L',
                         (SELECT "id" FROM "workspaces" WHERE "name" = 'default'));
        EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
        END;
        $$;


      ]], { TABLE = table_name }))

      table.insert(out, render([[

        -- Ensure (id, ws_id) pair is unique
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "$(TABLE)" ADD CONSTRAINT "$(TABLE)_id_ws_id_unique" UNIQUE ("id", "ws_id");
        EXCEPTION WHEN DUPLICATE_TABLE THEN
          -- Do nothing, accept existing state
        END$$;

      ]], { TABLE = table_name }))

      return table.concat(out, "\n")
    end,

    ----------------------------------------------------------------------------
    -- Make field unique per workspace only.
    -- @param table_name string: name of the table, e.g. "services"
    -- @param field_name string: name of the field, e.g. "name"
    -- @return string: SQL
    ws_unique_field = function(_, table_name, field_name)
      return render([[

          -- Make '$(TABLE).$(FIELD)' unique per workspace
          ALTER TABLE IF EXISTS ONLY "$(TABLE)" DROP CONSTRAINT IF EXISTS "$(TABLE)_$(FIELD)_key";

          -- Ensure (ws_id, $(FIELD)) pair is unique
          DO $$
          BEGIN
            ALTER TABLE IF EXISTS ONLY "$(TABLE)" ADD CONSTRAINT "$(TABLE)_ws_id_$(FIELD)_unique" UNIQUE ("ws_id", "$(FIELD)");
          EXCEPTION WHEN DUPLICATE_TABLE THEN
            -- Do nothing, accept existing state
          END$$;

      ]], {
        TABLE = table_name,
        FIELD = field_name,
      })
    end,

    ----------------------------------------------------------------------------
    -- Adjust foreign key to take ws_id into account and ensure it matches
    -- @param table_name string: name of the table e.g. "routes"
    -- @param fk_prefix string: name of the foreign field in the schema,
    -- which is used as a prefix in foreign key entries in tables e.g. "service"
    -- @param foreign_table_name string: name of the table the foreign field
    -- refers to e.g. "services"
    -- @return string: SQL
    ws_adjust_foreign_key = function(_, table_name, fk_prefix, foreign_table_name, is_cascade)
      return render([[

          -- Update foreign key relationship
          ALTER TABLE IF EXISTS ONLY "$(TABLE)" DROP CONSTRAINT IF EXISTS "$(TABLE)_$(FK)_id_fkey";

          DO $$
          BEGIN
            ALTER TABLE IF EXISTS ONLY "$(TABLE)"
                        ADD CONSTRAINT "$(TABLE)_$(FK)_id_fkey"
                           FOREIGN KEY ("$(FK)_id", "ws_id")
                            REFERENCES $(FOREIGN_TABLE)("id", "ws_id") $(CASCADE);
          EXCEPTION WHEN DUPLICATE_OBJECT THEN
            -- Do nothing, accept existing state
          END$$;

      ]], {
        TABLE = table_name,
        FK = fk_prefix,
        FOREIGN_TABLE = foreign_table_name,
        CASCADE = is_cascade and "ON DELETE CASCADE" or "",
      })
    end,

  },

  teardown = {

    ------------------------------------------------------------------------------
    -- Update composite cache keys to workspace-aware formats
    ws_update_composite_cache_key = function(_, connector, table_name, is_partitioned)
      local _, err = connector:query(render([[
        UPDATE "$(TABLE)"
        SET cache_key = CONCAT(cache_key, ':',
                               (SELECT id FROM workspaces WHERE name = 'default'))
        WHERE cache_key LIKE '%:';
      ]], {
        TABLE = table_name,
      }))
      if err then
        return nil, err
      end

      return true
    end,


    ------------------------------------------------------------------------------
    -- Update keys to workspace-aware formats
    ws_update_keys = function(_, connector, table_name, unique_keys)
      -- Reset default value for ws_id once it is populated
      local _, err = connector:query(render([[
        ALTER TABLE IF EXISTS ONLY "$(TABLE)" ALTER "ws_id" SET DEFAULT NULL;
      ]], {
        TABLE = table_name,
      }))
      if err then
        return nil, err
      end

      return true
    end,


    ------------------------------------------------------------------------------
    -- General function to fixup a plugin configuration
    fixup_plugin_config = function(_, connector, plugin_name, fixup_fn)
      local pgmoon_json = require("pgmoon.json")
      for plugin, err in connector:iterate("SELECT id, name, config FROM plugins") do
        if err then
          return nil, err
        end

        if plugin.name == plugin_name then
          local fix = fixup_fn(plugin.config)

          if fix then
            local sql = render(
              "UPDATE plugins SET config = $(NEW_CONFIG)::jsonb WHERE id = '$(ID)'", {
              NEW_CONFIG = pgmoon_json.encode_json(plugin.config),
              ID = plugin.id,
            })

            local _, err = connector:query(sql)
            if err then
              return nil, err
            end
          end
        end
      end

      return true
    end,
  },

}


--------------------------------------------------------------------------------
-- Higher-level operations for Workspace migration
--------------------------------------------------------------------------------


local function ws_adjust_fields(ops, entities)
  local out = {}

  for _, entity in ipairs(entities) do

    table.insert(out, ops:ws_add_ws_id(entity.name))

    for _, fk in ipairs(entity.fks) do
      table.insert(out, ops:ws_adjust_foreign_key(entity.name,
                                                  fk.name,
                                                  fk.reference,
                                                  fk.on_delete == "cascade"))
    end

    for _, unique in ipairs(entity.uniques) do
      table.insert(out, ops:ws_unique_field(entity.name, unique))
    end

  end

  return table.concat(out, "\n")
end


local function ws_adjust_data(ops, connector, entities)
  for _, entity in ipairs(entities) do
    if entity.cache_key and #entity.cache_key > 1 then
      local _, err = ops:ws_update_composite_cache_key(connector, entity.name, entity.partitioned)
      if err then
        return nil, err
      end
    end

    local _, err = ops:ws_update_keys(connector, entity.name, entity.uniques, entity.partitioned)
    if err then
      return nil, err
    end
  end

  return true
end


postgres.up.ws_adjust_fields = ws_adjust_fields


postgres.teardown.ws_adjust_data = ws_adjust_data


--------------------------------------------------------------------------------
-- Super high-level shortcut for plugins
--------------------------------------------------------------------------------


local function ws_migrate_plugin(plugin_entities)

  local function ws_migration_up(ops)
    return ops:ws_adjust_fields(plugin_entities)
  end

  local function ws_migration_teardown(ops)
    return function(connector)
      return ops:ws_adjust_data(connector, plugin_entities)
    end
  end

  return {
    postgres = {
      up = ws_migration_up(postgres.up),
      teardown = ws_migration_teardown(postgres.teardown),
    },
  }
end


--------------------------------------------------------------------------------


return {
  postgres = postgres,
  ws_migrate_plugin = ws_migrate_plugin,
}
