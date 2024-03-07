-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"


local SSL_DIR = "spec-ee/fixtures/hybrid-pki"

local CLUSTER_IP          = "127.0.0.1"
local CLUSTER_PORT        = 9005
local CLUSTER_LISTEN      = CLUSTER_IP .. ":" .. CLUSTER_PORT
local CLUSTER_SERVER_NAME = "server.kong.test"

local ERR = "data plane presented client certificate with incorrect CN " ..
            "during handshake"


local function cert_path(name)
  return SSL_DIR .. "/" .. name .. ".crt"
end

local function pkey_path(name)
  return SSL_DIR .. "/" .. name .. ".key"
end

local function get_data_planes()
  local admin_client = helpers.admin_client()

  local res = admin_client:get("/clustering/data-planes")
  assert.res_status(200, res,
                    "GET /clustering/data-planes returned non-200")

  local json = assert.response(res).has.jsonbody()
  assert.not_nil(json.data, "GET /clustering/data-planes response is malformed")

  admin_client:close()
  return json.data
end


local function new_cp(db, extra)
  local conf = {
    cluster_ca_cert          = cert_path("kong.test.ca"),
    cluster_cert             = cert_path("server.kong.test"),
    cluster_cert_key         = pkey_path("server.kong.test"),
    cluster_listen           = CLUSTER_LISTEN,
    cluster_mtls             = "pki_check_cn",
    cluster_server_name      = CLUSTER_SERVER_NAME,
    database                 = db,
    db_update_frequency      = 0.1,
    role                     = "control_plane",
  }

  for k, v in pairs(extra or {}) do
    conf[k] = v
  end

  return conf
end


local function connect_cp(cert, id)
  return helpers.clustering_client({
    cert        = cert_path(cert),
    cert_key    = pkey_path(cert),
    host        = CLUSTER_IP,
    node_id     = id,
    port        = CLUSTER_PORT,
    server_name = CLUSTER_SERVER_NAME,
  })
end


local function get_dp(id)
  local dps = get_data_planes()
  for _, dp in ipairs(dps) do
    if dp.id == id then
      return dp
    end
  end
end


local function check_dp_status(id, status)
  helpers.wait_until(function()
    local dp = get_dp(id)
    if dp then
      return dp.sync_status == status
    end
  end, 10, 0.5)
end


for _, strategy in helpers.each_strategy() do

describe("cluster_mtls(pki_check_cn) #" .. strategy, function()
  describe("empty cluster_allowed_common_names", function()
    local cp = new_cp(strategy)
    local db

    lazy_setup(function()
      local _
      _, db = helpers.get_db_utils(strategy, {
        "clustering_data_planes",
      })

      assert(helpers.start_kong(cp))
    end)

    lazy_teardown(function()
      helpers.stop_kong(cp.prefix)
    end)

    before_each(function()
      db.clustering_data_planes:truncate()

      helpers.pwait_until(function()
        local dps = get_data_planes()
        return  #dps == 0
      end, 10, 0.5)
    end)

    it("allows common names if they match the parent domain of the CP", function()
      local id = utils.uuid()
      local res, err = connect_cp("client.kong.test", id)
      assert.truthy(res, "CP connection failed unexpectedly: " .. tostring(err))

      check_dp_status(id, "normal")
      assert.errlog().has.no.line(ERR, true, 1)
    end)

    it("denies common names if they do not match the parent domain of the CP", function()
      local cert = "other.test"
      local res, err = connect_cp(cert)
      assert(res == nil and type(err) == "string",
             "CP connection succeeded unexpectedly")

      local msg = ERR .. ", got: " .. cert
      assert.errlog().has.line(msg, true, 10)
      assert.same({}, get_data_planes(),
                  "expected /clustering/data-planes to return empty")
    end)

  end)

  describe("non-empty cluster_allowed_common_names", function()
    local cp = new_cp(strategy, { cluster_allowed_common_names = "client.kong.test" })
    local db

    lazy_setup(function()
      local _
      _, db = helpers.get_db_utils(strategy, {
        "clustering_data_planes",
      })

      assert(helpers.start_kong(cp))
    end)

    lazy_teardown(function()
      helpers.stop_kong(cp.prefix)
    end)

    before_each(function()
      db.clustering_data_planes:truncate()

      helpers.wait_until(function()
        local dps = get_data_planes()
        return  #dps == 0
      end, 10, 0.5)
    end)

    it("allows common names if they are in the allowed list", function()
      local id = utils.uuid()
      local res, err = connect_cp("client.kong.test", id)
      assert.truthy(res, "CP connection failed unexpectedly: " .. tostring(err))

      check_dp_status(id, "normal")
      assert.errlog().has.no.line(ERR, true, 1)
    end)

    it("denies common names if they are not in the allowed list", function()
      local cert = "deny.kong.test"
      local res, err = connect_cp(cert)
      assert(res == nil and type(err) == "string",
             "CP connection succeeded unexpectedly")

      local msg = ERR .. ", got: " .. cert
      assert.errlog().has.line(msg, true, 10)

      assert.same({}, get_data_planes(),
                  "expected /clustering/data-planes to return empty")
    end)

  end)

end)

end
