local operations = require "kong.enterprise_edition.db.migrations.operations.1500_to_2100"
local log        = require "kong.cmd.utils.log"
local utils      = require "kong.tools.utils"

local render     = operations.utils.render

return {
  postgres = {
    up = '',
    teardown = function(connector)
      -- app_reg key_auth migrateion
      -- find all applications with oauth2, create and use oauth2 client_id as key_auth API key.

      local entities, err = connector:query([[
        SELECT app.consumer_id, oauth2_cred.client_id, app.ws_id 
        FROM applications app 
          LEFT JOIN oauth2_credentials oauth2_cred 
          ON app.consumer_id = oauth2_cred.consumer_id AND app.ws_id = oauth2_cred.ws_id;
      ]])

      if err then
        log.debug(err)
      end

      for _, entity in ipairs(entities) do
        local _, err = connector:query(render([[
          INSERT INTO keyauth_credentials (id, consumer_id, key, ws_id)
          VALUES ('$(ID)', '$(CONSUMER_ID)', '$(CLIENT_ID)', '$(WS_ID)');
        ]], {
          ID = utils.uuid(),
          CONSUMER_ID = entity.consumer_id,
          CLIENT_ID = entity.client_id,
          WS_ID = entity.ws_id,
        }))

        if err then
          return log.debug(err)
        end
      end

    end
  },
  cassandra = {
    up = '',
    teardown = function(connector)
      local coordinator = connector:connect_migrations()

      local cql = render([[
        SELECT consumer_id, ws_id FROM $(KEYSPACE).applications;
      ]], {
        KEYSPACE = connector.keyspace,
      })

      for rows, err in coordinator:iterate(cql) do
        
        if err then
          return log.debug(err)
        end

        for _, row in ipairs(rows) do

          local oauth2_creds, err = connector:query(render([[
            SELECT client_id from $(KEYSPACE).oauth2_credentials
            WHERE consumer_id=$(CONSUMER_ID)
              AND ws_id=$(WS_ID) ALLOW FILTERING;
          ]], {
            KEYSPACE = connector.keyspace,
            CONSUMER_ID = row.consumer_id,
            WS_ID = row.ws_id,
          }))

          if err then
            return log.debug(err)
          end

          for _, oauth2_cred in ipairs(oauth2_creds) do
            local _, err = connector:query(render([[
              INSERT INTO $(KEYSPACE).keyauth_credentials (id, consumer_id, key, ws_id)
              VALUES ($(ID), $(CONSUMER_ID), '$(CLIENT_ID)', $(WS_ID));
            ]], {
              KEYSPACE = connector.keyspace,
              ID = utils.uuid(),
              CONSUMER_ID = row.consumer_id,
              CLIENT_ID = oauth2_cred.client_id,
              WS_ID = row.ws_id,
            }))

            if err then
              return log.debug(err)
            end
          end

        end

      end
    end
  }
}
