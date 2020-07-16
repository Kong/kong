local helpers     = require "spec.helpers"
local listeners = require "kong.conf_loader.listeners"
local cjson = require "cjson.safe"
local assert = require "luassert"
local utils = require "kong.tools.utils"
local admins_helpers = require "kong.enterprise_edition.admins_helpers"


local _M = {}


function _M.register_rbac_resources(db, ws_name, ws_table)
  local bit   = require "bit"
  local rbac  = require "kong.rbac"
  local bxor  = bit.bxor

  local opts = ws_table and { workspace = ws_table.id }

  -- action int for all
  local action_bits_all = 0x0
  for k, v in pairs(rbac.actions_bitfields) do
    action_bits_all = bxor(action_bits_all, rbac.actions_bitfields[k])
  end

  local roles = {}
  local err, _
  -- now, create the roles and assign endpoint permissions to them

  -- first, a read-only role across everything
  roles.read_only, err = db.rbac_roles:insert({
    id = utils.uuid(),
    name = "read-only",
    comment = "Read-only access across all initial RBAC resources",
  }, opts)

  if err then
    return nil, nil, err
  end

  -- this role only has the 'read-only' permissions
  _, err = db.rbac_role_endpoints:insert({
    role = { id = roles.read_only.id, },
    workspace = ws_name or "*",
    endpoint = "*",
    actions = rbac.actions_bitfields.read,
  })

  ws_name = ws_name or "default"

  if err then
    return nil, nil, err
  end

  -- admin role with CRUD access to all resources except RBAC resource
  roles.admin, err = db.rbac_roles:insert({
    id = utils.uuid(),
    name = "admin",
    comment = "CRUD access to most initial resources (no RBAC)",
  }, opts)

  if err then
    return nil, nil, err
  end

  -- the 'admin' role has 'full-access' + 'no-rbac' permissions
  _, err = db.rbac_role_endpoints:insert({
    role = { id = roles.admin.id, },
    workspace = "*",
    endpoint = "*",
    actions = action_bits_all, -- all actions
  })

  if err then
    return nil, nil, err
  end

  local rbac_endpoints = { '/rbac/*', '/rbac/*/*', '/rbac/*/*/*' }
  for _, endpoint in ipairs(rbac_endpoints) do
    _, err = db.rbac_role_endpoints:insert({
      role = { id = roles.admin.id, },
      workspace = "*",
      endpoint = endpoint,
      negative = true,
      actions = action_bits_all, -- all actions
    })

    if err then
      return nil, nil, err
    end
  end

  -- finally, a super user role who has access to all initial resources
  roles.super_admin, err = db.rbac_roles:insert({
    id = utils.uuid(),
    name = "super-admin",
    comment = "Full CRUD access to all initial resources, including RBAC entities",
  }, opts)

  if err then
    return nil, nil, err
  end

  _, err = db.rbac_role_entities:insert({
    role = { id = roles.super_admin.id, },
    entity_id = "*",
    entity_type = "wildcard",
    actions = action_bits_all, -- all actions
  })

  if err then
    return nil, nil, err
  end

  _, err = db.rbac_role_endpoints:insert({
    role = { id = roles.super_admin.id, },
    workspace = "*",
    endpoint = "*",
    actions = action_bits_all, -- all actions
  })

  if err then
    return nil, nil, err
  end

  local super_admin, err = db.rbac_users:insert({
    id = utils.uuid(),
    name = "super_gruce-" .. ws_name,
    user_token = "letmein-" .. ws_name,
    enabled = true,
    comment = "Test - Initial RBAC Super Admin User"
  }, opts)

  if err then
    return nil, nil, err
  end

  local super_user_role, err = db.rbac_user_roles:insert({
    user = super_admin,
    role = roles.super_admin,
  })

  if err then
    return nil, nil, err
  end

  return super_admin, super_user_role
end


--- returns a pre-configured `http_client` for the Kong admin gui.
-- @name admin_gui_client
function _M.admin_gui_client(timeout, forced_port)
  local admin_ip, admin_port
  for _, entry in ipairs(_M.admin_gui_listeners) do
    if entry.ssl == false then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  assert(admin_ip, "No http-admin found in the configuration")
  return helpers.http_client(admin_ip, forced_port or admin_port, timeout or 60000)
end

--- Returns the Dev Portal port.
-- @param ssl (boolean) if `true` returns the ssl port
local function get_portal_api_port(ssl)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(_M.portal_api_listeners) do
    if entry.ssl == ssl then
      return entry.port
    end
  end
  error("No portal port found for ssl=" .. tostring(ssl), 2)
end


--- Returns the Dev Portal ip.
-- @param ssl (boolean) if `true` returns the ssl ip address
local function get_portal_api_ip(ssl)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(_M.portal_api_listeners) do
    if entry.ssl == ssl then
      return entry.ip
    end
  end
  error("No portal ip found for ssl=" .. tostring(ssl), 2)
end


--- Returns the Dev Portal port.
-- @param ssl (boolean) if `true` returns the ssl port
local function get_portal_gui_port(ssl)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(_M.portal_gui_listeners) do
    if entry.ssl == ssl then
      return entry.port
    end
  end
  error("No portal port found for ssl=" .. tostring(ssl), 2)
end


--- Returns the Dev Portal ip.
-- @param ssl (boolean) if `true` returns the ssl ip address
local function get_portal_gui_ip(ssl)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(_M.portal_gui_listeners) do
    if entry.ssl == ssl then
      return entry.ip
    end
  end
  error("No portal ip found for ssl=" .. tostring(ssl), 2)
end


--- returns a pre-configured `http_client` for the Dev Portal.
-- @name portal_client
function _M.portal_api_client(timeout)
  local portal_ip = get_portal_api_ip()
  local portal_port = get_portal_api_port()
  assert(portal_ip, "No portal_ip found in the configuration")
  return helpers.http_client(portal_ip, portal_port, timeout)
end


function _M.portal_gui_client(timeout)
  local portal_ip = get_portal_gui_ip()
  local portal_port = get_portal_gui_port()
  assert(portal_ip, "No portal_ip found in the configuration")
  return helpers.http_client(portal_ip, portal_port, timeout)
end


function _M.post(client, path, body, headers, expected_status)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "POST",
    path = path,
    body = body or {},
    headers = headers
  })
  return cjson.decode(assert.res_status(expected_status or 201, res))
end


function _M.create_admin(email, custom_id, status, db, username, workspace)
  local opts = workspace and { workspace = workspace.id }

  local admin = assert(db.admins:insert({
    username = username or email,
    custom_id = custom_id,
    email = email,
    status = status,
  }, opts))

  local token_res, err = admins_helpers.update_token(admin)
  if err then
    return nil, err
  end

  -- only used for tests so we can reference token
  -- WARNING: do not do this outside test environment
  admin.rbac_user.raw_user_token = token_res.body.token

  return admin
end


function _M.get_admin_cookie_basic_auth(client, username, password)
  local res = assert(client:send {
    method = "GET",
    path = "/auth",
    headers = {
      ["Authorization"] = "Basic " .. ngx.encode_base64(username .. ":"
                                                        .. password),
      ["Kong-Admin-User"] = username,
    }
  })

  assert.res_status(200, res)
  return res.headers["Set-Cookie"]
end


local http_flags = { "ssl", "http2", "proxy_protocol", "transparent" }
_M.portal_api_listeners = listeners._parse_listeners(helpers.test_conf.portal_api_listen, http_flags)
_M.portal_gui_listeners = listeners._parse_listeners(helpers.test_conf.portal_gui_listen, http_flags)
_M.admin_gui_listeners = listeners._parse_listeners(helpers.test_conf.admin_gui_listen, http_flags)

return _M
