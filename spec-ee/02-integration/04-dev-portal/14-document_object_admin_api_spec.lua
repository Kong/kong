-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers      = require "spec.helpers"
local cjson        = require "cjson"
local clear_license_env = require("spec-ee.02-integration.04-dev-portal.utils").clear_license_env

local function close_clients(clients)
  for idx, client in ipairs(clients) do
    client:close()
  end
end


local function client_request(params)
  local client = assert(helpers.admin_client())
  local res = assert(client:send(params))
  res.body = res:read_body()
  res.body = cjson.decode(res.body)

  close_clients({ client })
  return res
end

local function configure_portal(db, config)
  config = config or {
    portal = true,
  }

  db.workspaces:update_by_name("default", {
    name = "default",
    config = config,
  })
end

local function post_file(path, contents)
  local res = client_request({
    method = "POST",
    path = "/files",
    body = {
      path = path,
      contents = contents,
    },
    headers = {["Content-Type"] = 'application/json'}
  })

  return res
end

local function truncate_tables(db)
  assert(db:truncate("document_objects"))
  assert(db:truncate("files"))
  assert(db:truncate("services"))
end


for _, strategy in helpers.each_strategy() do
  describe("Document Objects [#" .. strategy .. "]", function()
    local db, service_id
    local reset_license_data

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy)
      reset_license_data = clear_license_env()

      assert(helpers.start_kong({
        database    = strategy,
        portal      = true,
        portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
        portal_is_legacy = false,
        license_path = "spec-ee/fixtures/mock_license.json",
        enforce_rbac = "off",
      }))

      kong.configuration = {
        portal_is_legacy = false,
      }

      configure_portal(db)
    end)

    before_each(function()
      truncate_tables(db)

      local res = client_request({
        method = "POST",
        path = "/services",
        body = {
          host = "mockbin.org"
        },
        headers = {["Content-Type"] = "application/json"}
      })

      assert.equal(201, res.status)
      assert.is_string(res.body.id)

      service_id = res.body.id
    end)

    lazy_teardown(function()
      truncate_tables(db)
      helpers.stop_kong(nil, true)
      reset_license_data()
    end)

    describe("/document_objects", function()
      it("should replace document_object already linked to service", function()
        local file_path_1 = "docs/test1.md"
        local file_path_2 = "docs/test2.md"
        local contents = [[
# Hello World
]]

        local res = post_file(file_path_1, contents)
        assert.equal(201, res.status)

        res = post_file(file_path_2, contents)
        assert.equal(201, res.status)

        res = client_request({
          method = "POST",
          path = "/document_objects",
          body = {
            path = file_path_1,
            service = { id = service_id }
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equal(201, res.status)

        res = client_request({
          method = "GET",
          path = "/document_objects",
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equal(#res.body.data, 1)
        assert.equal(res.body.data[1].path, file_path_1)

        res = client_request({
          method = "POST",
          path = "/document_objects",
          body = {
            path = file_path_2,
            service = { id = service_id }
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equal(201, res.status)

        res = client_request({
          method = "GET",
          path = "/document_objects",
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equal(#res.body.data, 1)
        assert.equal(res.body.data[1].path, file_path_2)
      end)

      it("should not allow posting a file path that doesn't exist", function()
        local res = client_request({
          method = "POST",
          path = "/document_objects",
          body = {
            path = 'docs/not-found',
            service = { id = service_id }
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equal(404, res.status)
        assert.equal("File at path docs/not-found not found", res.body.message)
      end)
    end)

    describe("services/:id/document_objects", function()
      it("should replace document_object already linked to service", function()
        local file_path_1 = "docs/test1.md"
        local file_path_2 = "docs/test2.md"
        local contents = [[
# Hello World
]]

        local res = post_file(file_path_1, contents)
        assert.equal(201, res.status)

        res = post_file(file_path_2, contents)
        assert.equal(201, res.status)

        -- link a file to the service
        res = client_request({
          method = "POST",
          path = "/services/"..service_id.."/document_objects",
          body = {
            path = file_path_1,
            service = { id = service_id }
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equal(200, res.status)

        res = client_request({
          method = "GET",
          path = "/services/"..service_id.."/document_objects",
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equal(#res.body.data, 1)
        assert.equal(res.body.data[1].path, file_path_1)

        -- post another file to the service, should overwrite the first
        res = client_request({
          method = "POST",
          path = "/services/"..service_id.."/document_objects",
          body = {
            path = file_path_2,
            service = { id = service_id }
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equal(200, res.status)

        res = client_request({
          method = "GET",
          path = "/services/"..service_id.."/document_objects",
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equal(#res.body.data, 1)
        assert.equal(res.body.data[1].path, file_path_2)
      end)

      it("should not allow posting a file path that doesn't exist", function()
        local res = client_request({
          method = "POST",
          path = "/services/"..service_id.."/document_objects",
          body = {
            path = 'docs/not-found',
            service = { id = service_id }
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equal(404, res.status)
        assert.equal("Not found", res.body.message)
      end)
    end)


  end)
end
