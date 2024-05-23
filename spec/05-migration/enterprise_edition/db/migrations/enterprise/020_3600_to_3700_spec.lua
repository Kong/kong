-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uh = require "spec/upgrade_helpers"
local cjson = require "cjson"
local helpers = require "spec.helpers"

local OLD_KONG_VERSION = os.getenv("OLD_KONG_VERSION")
local handler = OLD_KONG_VERSION:sub(1,8) == "next/2.8" and describe or pending

if uh.database_type() == 'postgres' then
  handler("audit_objects default timestamp", function()
      lazy_setup(function()
          assert(uh.start_kong({
            audit_log  = "on",
            audit_log_ignore_paths = [[/audit/(requests|objects)(\?.+)?]],
          }))
      end)

      lazy_teardown(function ()
          assert(uh.stop_kong())
      end)

      uh.setup(function ()
          local admin_client = assert(uh.admin_client())

          -- create a few entities
          assert.res_status(201, admin_client:post("/consumers", {
            body = { username = "c1" },
            headers = {["Content-Type"] = "application/json"}
          }))
          local res = assert.res_status(201, admin_client:post("/consumers", {
            body = { username = "c2" },
            headers = {["Content-Type"] = "application/json"}
          }))
          local json = cjson.decode(res)
          assert.res_status(200, admin_client:patch("/consumers/" .. json.id, {
            body = { username = "c2-updated" },
            headers = {["Content-Type"] = "application/json"}
          }))

          -- validate if audit_objects were created
          helpers.wait_until(function()
            res = assert.res_status(200, admin_client:send({path = "/audit/objects"}))
            json = cjson.decode(res)
            return #json.data == 3
          end, 5, 0.5)

          assert.is_nil(json.data[1].request_timestamp)
          assert.is_nil(json.data[2].request_timestamp)
          assert.is_nil(json.data[3].request_timestamp)

          admin_client:close()
      end)

      uh.new_after_up("has updated request_timestamp to 1", function ()
          assert.table_has_column("audit_objects", "request_timestamp", "timestamp without time zone")
          assert.table_has_index("audit_objects", "audit_objects_request_timestamp_idx")
          assert.table_has_index("audit_requests", "audit_requests_request_timestamp_idx")

          local admin_client = assert(uh.admin_client())

          local res = assert.res_status(200, admin_client:send({path = "/audit/objects"}))
          local json = cjson.decode(res)
          assert.same(3, #json.data)
          assert.same(1, json.data[1].request_timestamp)
          assert.same(1, json.data[2].request_timestamp)
          assert.same(1, json.data[3].request_timestamp)

          admin_client:close()
      end)
  end)
end
