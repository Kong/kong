return {
    postgres = {
      up = [[
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "services" ADD "enabled" BOOLEAN DEFAULT true;
        EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
        END;
        $$;
      ]]
    },
  
    cassandra = {
      up = [[
        ALTER TABLE services ADD enabled boolean;
      ]],
      teardown = function(connector)
        local coordinator = assert(connector:get_stored_connection())
        local cassandra = require "cassandra"

        for rows, err in coordinator:iterate("SELECT partition, id, enabled FROM services") do
          if err then
            return nil, err
          end

          for _, row in ipairs(rows) do
            if not row.enabled then
              local _, err = coordinator:execute("UPDATE services SET enabled = ? WHERE partition = ? AND id = ?", {
                cassandra.boolean(true),
                cassandra.text(row.partition),
                cassandra.uuid(row.id),
              })
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
  