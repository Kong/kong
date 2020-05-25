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
    }
  },
  general = {
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
