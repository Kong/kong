-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  known = {
    general_files = {
      -- "kong/api/routes/kong.lua",
      "kong/api/routes/admins.lua",
      "kong/api/routes/applications.lua",
      "kong/api/routes/audit.lua",
      "kong/api/routes/consumer_groups.lua",
      "kong/api/routes/developers.lua",
      "kong/api/routes/entities.lua",
      "kong/api/routes/event_hooks.lua",
      "kong/api/routes/files.lua",
      "kong/api/routes/groups.lua",
      "kong/api/routes/keyring.lua",
      "kong/api/routes/license.lua",
      "kong/api/routes/rbac.lua",
      "kong/api/routes/vitals.lua",
      "kong/api/routes/workspaces.lua",
    },
    entities = {
      services = {
        ["/services/:services/document_objects"] = {
          endpoint = false,
        },
      },
    },
  },

  general = {
    kong = {
      -- userinfo and auth have to be documented in the CE one
      ["/userinfo"] = {},       --  ee?
      ["/auth"] = {},           --  ee?
    },
    admins = { -- FIXME fix these endpoints, or make Admins generated
      title = [[Admins routes]],
      description = "",
      ["/admins"] = {
        GET = {
          title = [[Retrieve all Admins]],
          endpoint = [[<div class="endpoint get">/admins</div>]],
          description =[[
          Retrieve all the Admins in Kong.
        ]],
          response = [[
          ```
          HTTP 200 OK
          ```

          ```json
          {
            {
              "data": [
                { "id": "123",
                  "created_at": 123,
                  "updated_at":  123,
                  "username": "admin1",
                  "custom_id": "admin1",
                  "email":  "admin1@example.dev",
                  "status": 1,
                  "rbac_token_enabled": false,
                  "consumer":  { id = "abc" }
                  "rbac_user": { id = "def" }
                }
              ],
              "offset": "123",
              "next": "/admins?offset=123"
            },
          }
          ```
        ]]
        },
        POST = {
          title = [[Create Admin]],
          endpoint = [[<div class="endpoint post">/admins</div>]],
          description = [[
          Create a new Admin.
        ]],
          response = [[
          ```
          HTTP 201 Created
          ```

          ```json
          { "id": "123",
            "created_at": 123,
            "updated_at":  123,
            "username": "admin1",
            "custom_id": "admin1",
            "email":  "admin1@example.dev",
            "status": 1,
            "rbac_token_enabled": false,
            "consumer":  { id = "abc" }
            "rbac_user": { id = "def" }
          }
          ```
        ]]
        },
      },
      ["/admins/:admins"] = {},
      ["/admins/:admin/roles"] = {},
      ["/admins/self/token"] = {},
      ["/admins/:admin/workspaces"] = {},
      ["/admins/password_resets"] = {},
      ["/admins/self/password"] = {},
      ["/admins/register"] = {},

    }, -- FIXME keep adding endpoints here

    applications = {
      description = [[ applications endpoints ]],
        ["/applications"] = {},
        ["/applications/:applications"] = {},
        ["/applications/:applications/application_instances"] = {},
        ["/applications/:applications/application_instances/:application_instances"] = {},
        ["/applications/:applications/credentials/:plugin"] = {},
        ["/applications/:applications/credentials/:plugin/:credential_id"] = {},
    },

    audit = {
      description = [[ audit endpoints ]],
        ["/audit/requests"] = {},
        ["/audit/objects"] = {},
    },

    consumer_groups = {
      description = [[ consumer_groups endpoints ]],
      ["/consumer_groups"] = {},
      ["/consumer_groups/:consumer_groups"] = {},
      ["/consumer_groups/:consumer_groups/consumers"] = {},
      ["/consumer_groups/:consumer_groups/consumers/:consumers"] = {},
      ["/consumer_groups/:consumer_groups/overrides/plugins/rate-limiting-advanced"] = {},
      ["/consumers/:consumers/consumer_groups"] = {},
      ["/consumers/:consumers/consumer_groups/:consumer_groups"] = {},
    },

    developers = {
      description = [[ developers endpoints]],
      ["/developers"] = {},
      ["/developers/roles"] = {},
      ["/developers/roles/:rbac_roles"] = {},
      ["/developers/:developers"] = {},
      ["/developers/:developers/applications"] = {},
      ["/developers/:developers/applications/:applications"] = {},
      ["/developers/:developers/applications/:applications/credentials/:plugin"] = {},
      ["/developers/:developers/applications/:applications/credentials/:plugin/:credential_id"] = {},
      ["/developers/:developers/applications/:applications/application_instances"] = {},
      ["/developers/:developers/applications/:applications/application_instances/:application_instances"] = {},
      ["/developers/:developers/plugins/"] = {},
      ["/developers/:developers/plugins/:id"] = {},
      ["/developers/:developers/credentials/:plugin"] = {},
      ["/developers/:developers/credentials/:plugin/:credential_id"] = {},
      ["/developers/invite"] = {},
      ["/developers/export"] = {},
    },
    entities = {
      description = [[ entities endpoints]],
      ["/entities/migrate"] = {},
    },
    event_hooks = {
      description = [[ event_hooks endpoints]],
      ["/event-hooks"] = {},
      ["/event-hooks/:event_hooks"] = {},
      ["/event-hooks/:event_hooks/test"] = {},
      ["/event-hooks/:event_hooks/ping"] = {},
      ["/event-hooks/sources"] = {},
      ["/event-hooks/sources/:source"] = {},
      ["/event-hooks/sources/:source/:event"] = {},
    },

    files = {
      description = [[ files endpoints]],
      ["/files"] = {},
      ["/files/partials/*"] = {},
      ["/files/:files"] = {},
    },

    groups = {
      description = [[ groups endpoints]],
      ["/groups"] = {},
      ["/groups/:groups"] = {},
      ["/groups/:groups/roles"] = {},
    },

    keyring = {
      description = [[ keyring endpoints ]],
      ["/keyring"] = {},
      ["/keyring/active"] = {},
      ["/keyring/export"] = {},
      ["/keyring/import"] = {},
      ["/keyring/import/raw"] = {},
      ["/keyring/generate"] = {},
      ["/keyring/activate"] = {},
      ["/keyring/remove"] = {},
      ["/keyring/vault/sync"] = {},
      ["/keyring/recover"] = {},
    },

    license = {
      description = [[ license endpoints ]],
      ["/license/report"] = {},
    },

    rbac = {
      description = [[ rbac endpoints ]],

      ["/rbac/users"] = {},
      ["/rbac/users/:rbac_users"] = {},
      ["/rbac/users/:rbac_users/permissions"] = {},
      ["/rbac/users/:rbac_users/roles"] = {},
      ["/rbac/roles"] = {},
      ["/rbac/roles/:rbac_roles/permissions"] = {},
      ["/rbac/roles/:rbac_roles"] = {},
      ["/rbac/roles/:rbac_roles/entities"] = {},
      ["/rbac/roles/:rbac_roles/entities/:entity_id"] = {},
      ["/rbac/roles/:rbac_roles/entities/permissions"] = {},
      ["/rbac/roles/:rbac_roles/endpoints"] = {},
      ["/rbac/roles/:rbac_roles/endpoints/:workspace/*"] = {},
      ["/rbac/roles/:rbac_roles/endpoints/permissions"] = {},
   },

    vitals = {
      description = [[ vitals endpoints ]],
      ["/vitals/"] = {},
      ["/vitals/cluster"] = {},
      ["/vitals/cluster/status_codes"] = {},
      ["/vitals/nodes/"] = {},
      ["/vitals/nodes/:node_id"] = {},
      ["/vitals/consumers/:consumer_id/cluster"] = {},
      ["/vitals/status_codes/by_service"] = {},
      ["/vitals/status_codes/by_route"] = {},
      ["/vitals/status_codes/by_consumer"] = {},
      ["/vitals/status_codes/by_consumer_and_route"] = {},
      ["/vitals/status_code_classes"] = {},
      ["/vitals/reports/:entity_type"] = {},
    },

    workspaces = {
      description = [[ workspaces endpoints ]],
["/workspaces"] = {},
["/workspaces/:workspaces"] = {},
["/workspaces/:workspaces/entities"] = {},
["/workspaces/:workspaces/entities/:entity_id"] = {},
["/workspaces/:workspaces/meta"] = {},
    },

  }
}
