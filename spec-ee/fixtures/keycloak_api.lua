-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- references docs
-- https://www.keycloak.org/docs-api/23.0.4/rest-api/index.html

local fmt = string.format

local KEYCLOAK_IP         = os.getenv("KONG_SPEC_TEST_KEYCLOAK_HOST") or "keycloak"
local KEYCLOAK_PORT       = os.getenv("KONG_SPEC_TEST_KEYCLOAK_PORT_8080") or "8080"
local KEYCLOAK_SSL_PORT   = "8443"
local KEYCLOAK_CLIENT_ID  = "admin-cli"
local KEYCLOAK_USERNAME   = "admin"
local KEYCLOAK_PASSWORD   = "test" -- retrieve the password from the openid-connect/.pongo/keycloak.yml
local KEYCLOAK_GRANT_TYPE = "password"
local KEYCLOAK_REALM      = "demo"

local KONG_CLIENT_ID      = "kong-client-secret"
local KONG_CLIENT_SECRET  = "38beb963-2786-42b8-8e14-a5f391b4ba93"

local function api_uri(path, ...)
  local prefix = fmt("/admin/realms/%s", KEYCLOAK_REALM)
  return prefix .. fmt(path, ...)
end

local function cloak_settings()
  return {
    realm = KEYCLOAK_REALM,
    issuer = fmt("http://%s:%s/realms/%s/.well-known/openid-configuration",
      KEYCLOAK_IP,
      KEYCLOAK_PORT,
      KEYCLOAK_REALM
    ),
    ssl_issuer = fmt("https://%s:%s/realms/%s/.well-known/openid-configuration",
      KEYCLOAK_IP,
      KEYCLOAK_SSL_PORT,
      KEYCLOAK_REALM
    ),
    ip = KEYCLOAK_IP,
    port = KEYCLOAK_PORT,
    ssl_port = KEYCLOAK_SSL_PORT,
    host = KEYCLOAK_IP .. ":" .. KEYCLOAK_PORT,
    ssl_host = KEYCLOAK_IP .. ":" .. KEYCLOAK_SSL_PORT,
    client_id = KONG_CLIENT_ID,
    client_secret = KONG_CLIENT_SECRET,
  }
end

-- return 200
local function auth(client)
  local url = "/realms/master/protocol/openid-connect/token"
  return client:send {
    method = "POST",
    path = url,
    body = {
      client_id = KEYCLOAK_CLIENT_ID,
      username = KEYCLOAK_USERNAME,
      password = KEYCLOAK_PASSWORD,
      grant_type = KEYCLOAK_GRANT_TYPE,
    },
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    }
  }
end

-- return 201
local function add_user(client, access_token, body)
  return client:send {
    method = "POST",
    body = body,
    path = api_uri("/users"),
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = access_token,
    }
  }
end

-- return 204
local function delete_user(client, access_token, user_id)
  return client:send {
    method = "DELETE",
    path = api_uri("/users/%s", user_id),
    headers = {
      ["Authorization"] = access_token,
    }
  }
end

-- return 200,
-- return userList
-- https://www.keycloak.org/docs-api/23.0.4/rest-api/index.html#_users
local function get_users(client, access_token, username)
  return client:send {
    method = "GET",
    path = api_uri("/users?exact=true&max=10&username=%s", username),
    headers = {
      ["Authorization"] = access_token,
    }
  }
end

-- return 201, no body
-- https://www.keycloak.org/docs-api/23.0.4/rest-api/index.html#_groups
local function add_group(client, access_token, body)
  return client:send {
    method = "POST",
    path = api_uri("/groups"),
    body = body,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = access_token,
    }
  }
end

-- return 204, no body
local function delete_group(client, access_token, group_id)
  return client:send {
    method = "DELETE",
    path = api_uri("/groups/%s", group_id),
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = access_token,
    }
  }
end

-- return 200
-- return groups
local function get_groups(client, access_token, name)
  return client:send {
    method = "GET",
    path = api_uri("/groups?exact=true&max=10&search=%s", name),
    headers = {
      ["Authorization"] = access_token,
    }
  }
end

-- return 204, no body
local function add_group_to_user(client, access_token, user_id, group_id)
  return client:send {
    method = "PUT",
    path = api_uri("/users/%s/groups/%s", user_id, group_id),
    headers = {
      ["Authorization"] = access_token,
    }
  }
end

-- return 204, no body
local function delete_group_from_user(client, access_token, user_id, group_id)
  return client:send {
    method = "DELETE",
    path = api_uri("/users/%s/groups/%s", user_id, group_id),
    headers = {
      ["Authorization"] = access_token,
    }
  }
end

return {
  cloak_settings = cloak_settings,
  auth = auth,
  add_user = add_user,
  delete_user = delete_user,
  add_group = add_group,
  delete_group = delete_group,
  get_users = get_users,
  get_groups = get_groups,
  add_group_to_user = add_group_to_user,
  delete_group_from_user = delete_group_from_user
}
