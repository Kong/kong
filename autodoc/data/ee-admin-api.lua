return {
  known = {
    general_files = {
      "kong/api/routes/admins.lua",
      "kong/api/routes/applications.lua",
      "kong/api/routes/audit.lua",
      "kong/api/routes/developers.lua",
      "kong/api/routes/entities.lua",
      "kong/api/routes/event_hooks.lua",
      "kong/api/routes/files.lua",
      "kong/api/routes/groups.lua",
      "kong/api/routes/keyring.lua",
      "kong/api/routes/license.lua",
      "kong/api/routes/oas_config.lua",
      "kong/api/routes/rbac.lua",
      "kong/api/routes/vitals.lua",
      "kong/api/routes/workspaces.lua",
    }
  },
  entities = {
    services = {
      ["/services/:services/document_objects"] = {
        endpoint = false,
      },
    },
  },
  general = {
    kong = {

      ["/userinfo"] = {
        GET = {
          title = [[userinfo info]],
          endpoint = [[<div class="endpoint get">/userinfo</div>]],
          description =[[
            Retrieve user info.
          ]],
          response = [[]],
        }
      },

      ["/auth"] = {},
      ["/admins"] = {},
      ["/admins/:admins"] = {},
      ["/admins/:admin/roles"] = {},
      ["/admins/password_resets"] = {},
      ["/admins/:admin/workspaces"] = {},
      ["/admins/register"] = {},
      ["/admins/self/password"] = {},
      ["/admins/self/token"] = {},



["/applications"] = {},
["/applications/:applications"] = {},
["/applications/:applications/application_instances"] = {},
["/applications/:applications/application_instances/:application_instances"] = {},
["/applications/:applications/credentials/:plugin"] = {},
["/applications/:applications/credentials/:plugin/:credential_id"] = {},


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
["/developers/:email_or_id/plugins/"] = {},
["/developers/:email_or_id/plugins/:id"] = {},
["/developers/:developers/credentials/:plugin"] = {},
["/developers/:developers/credentials/:plugin/:credential_id"] = {},
["/developers/invite"] = {},

  ["/entities/migrate"] = {},


["/event-hooks"] = {},
["/event-hooks/:event_hooks"] = {},
["/event-hooks/:event_hooks/test"] = {},
["/event-hooks/:event_hooks/ping"] = {},
["/event-hooks/sources"] = {},
["/event-hooks/sources/:source"] = {},
["/event-hooks/sources/:source/:event"] = {},

  ["/files"] = {},
  ["/files/partials/*"] = {},
  ["/files/:files"] = {},



["/groups"] = {},
["/groups/:groups"] = {},
["/groups/:groups/roles"] = {},

  ["/keyring"] = {},
  ["/keyring/active"] = {},
  ["/keyring/export"] = {},
  ["/keyring/import"] = {},
  ["/keyring/import/raw"] = {},
  ["/keyring/generate"] = {},
  ["/keyring/activate"] = {},
  ["/keyring/remove"] = {},
  ["/keyring/vault/sync"] = {},

  ["/license/report"] = {},



  ["/oas-config"] = {},

["/workspaces"] = {},
["/workspaces/:workspaces"] = {},
["/workspaces/:workspaces/entities"] = {},
["/workspaces/:workspaces/entities/:entity_id"] = {},
["/workspaces/:workspaces/meta"] = {},

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
    admins = { -- FIXME fix these endpoints, or make Admins generated
      title = [[Admins routes]],
      description = "",
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
    }, -- FIXME keep adding endpoints here

    applications = {
      description = [[ applications endpoints ]],
    },
    audit = {
      description = [[ audit endpoints ]],
    },

    developers = {
      description = [[ developers endpoints]]
    },
    entities = {
      description = [[ entities endpoints]]
    },
    event_hooks = {
      description = [[ event_hooks endpoints]]
    },
    files = {
      description = [[ files endpoints]]
    },
    groups = {
      description = [[ groups endpoints]]
    },
    keyring = {
      description = [[ keyring endpoints ]]
    },
    license = {
      description = [[ license endpoints ]]
    },
    oas_config = {
      description = [[ oas_config endpoints ]]
    },
    rbac = {
      description = [[ rbac endpoints ]]
    },
    vitals = {
      description = [[ vitals endpoints ]]
    },
    workspaces = {
      description = [[ workspaces endpoints ]]
    },
  }
}
