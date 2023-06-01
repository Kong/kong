-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
}
