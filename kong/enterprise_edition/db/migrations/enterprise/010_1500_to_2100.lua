return {
    postgres = {
      up = [[
        CREATE TABLE IF NOT EXISTS "ws_migrations_backup" (
            "entity_type"               TEXT,
            "entity_id"                 TEXT,
            "unique_field_name"         TEXT,
            "unique_field_value"        TEXT,
            "created_at"                TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC')
          );
      ]],
      teardown = function(connector)
      end,
    },
  
    cassandra = {
      up = [[
        
      ]],
      teardown = function(connector)
      end,
    }
  }
  