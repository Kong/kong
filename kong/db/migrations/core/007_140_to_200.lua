local fmt = string.format
local cassandra = require "cassandra"

local PATH_HANDLING_WHEN_MIGRATING_FROM = {
  ["000_base"]       = "v0",
  ["001_14_to_15"]   = "v0",
  ["002_15_to_1"]    = "v0",
  ["003_100_to_110"] = "v1",
  ["004_110_to_120"] = "v1",
  ["005_120_to_130"] = "v1",
  ["006_130_to_140"] = "v1",
}


local pg_path_handling_sql do
  local v0_conds = {}
  local v1_conds = {}
  for migration, vx in pairs(PATH_HANDLING_WHEN_MIGRATING_FROM) do
    local conds = vx == "v0" and v0_conds or v1_conds
    conds[#conds + 1] = fmt("migrating_from = '%s'", migration)
  end
  table.sort(v0_conds)
  table.sort(v1_conds)
  v0_conds = table.concat(v0_conds, "\n      OR ")
  v1_conds = table.concat(v1_conds, "\n         OR ")

  pg_path_handling_sql = fmt([[
    DO $$
    BEGIN
      ALTER TABLE IF EXISTS ONLY "routes" ADD "path_handling" TEXT;
    EXCEPTION WHEN DUPLICATE_COLUMN THEN
      -- Do nothing, accept existing state
    END;
    $$;

    DO $$
    DECLARE
      migrating_from TEXT;
    BEGIN
      SELECT last_executed INTO migrating_from FROM schema_meta WHERE subsystem = 'core';
      IF %s
      THEN
        UPDATE routes SET path_handling = 'v0';
      ELSIF %s
      THEN
        UPDATE routes SET path_handling = 'v1';
      END IF;
    END;
    $$;
  ]], v0_conds, v1_conds)
end


return {
  postgres = {
    up = pg_path_handling_sql,

    teardown = function(connector)
      assert(connector:query([[
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "plugins" DROP COLUMN "run_on";
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END;
        $$;


        DO $$
        BEGIN
          DROP TABLE IF EXISTS "cluster_ca";
        END;
        $$;
      ]]))
    end,
  },

  cassandra = {
    up = function(connector)
      local res, err = connector:query([[
        ALTER TABLE routes ADD path_handling text;
      ]])

      if not res then
        if connector:is_ignorable_during_migrations(err) then
          ngx.log(ngx.WARN, fmt(
            "ignored error while running '007_140_to_200' migration: %s (%s)",
            err, "ALTER TABLE routes ADD path_handling text;"
          ))
        else
          return nil, err
        end
      end

      local rows = assert(connector:query([[
        SELECT last_executed FROM schema_meta
          WHERE key = ? AND subsystem = ?
      ]], {
        cassandra.text("007_140_to_200"),
        cassandra.text("path_handling")
      }))
      local preset_path_handling = rows and rows[1] and rows[1].last_executed

      if not preset_path_handling then
        local rows = assert(connector:query([[
          SELECT last_executed FROM schema_meta
            WHERE key = ? AND subsystem = ?
        ]], {
          cassandra.text("schema_meta"),
          cassandra.text("core")
        }))
        local migrating_from = rows and rows[1] and rows[1].last_executed

        if migrating_from then
          preset_path_handling = PATH_HANDLING_WHEN_MIGRATING_FROM[migrating_from]
        end
      end

      if preset_path_handling then
        assert(connector:query([[
          INSERT INTO schema_meta (key, subsystem, last_executed)
            VALUES(?, ?, ?)
        ]], {
          cassandra.text("007_140_to_200"),
          cassandra.text("path_handling"),
          cassandra.text(preset_path_handling)
        }))

        local rows = assert(connector:query([[
          SELECT id FROM routes;
        ]]))
        for i = 1, #rows do
          assert(connector:query(
            "UPDATE routes SET path_handling = ? WHERE id = ?",
            { cassandra.text(preset_path_handling),
              cassandra.text(rows[i].id)
            }
          ))
        end
      end
    end,

    teardown = function(connector)
      assert(connector:query([[
        DROP INDEX IF EXISTS plugins_run_on_idx;
        ALTER TABLE plugins DROP run_on;


        DROP TABLE IF EXISTS cluster_ca;
      ]]))
    end,
  },
}
