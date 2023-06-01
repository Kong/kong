-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local operations = require "kong.enterprise_edition.db.migrations.operations.1500_to_2100"
local log          = require "kong.cmd.utils.log"

local postgres_has_workspace_enitites = operations.utils.postgres_has_workspace_entities
--------------------------------------------------------------------------------

return {
  -- revert migration for:
  -- https://github.com/Kong/kong-ee/commit/64f56f079236336d55a4116e85e04e629357b87e

  postgres = {
    up = [[]],
    teardown = function (connector)
      if not postgres_has_workspace_enitites(nil, connector)[1] then
        return nil
      end

      local _, err = connector:query([[

        -- revert consumers ws_id from workspace_entities table

        UPDATE consumers
        SET ws_id = we.workspace_id
        FROM workspace_entities we
        WHERE entity_type='consumers'
          AND unique_field_name='id'
          AND unique_field_value=consumers.id::text;
      ]])

      if err then
        log.debug(err)
      end
    end
  },
}
