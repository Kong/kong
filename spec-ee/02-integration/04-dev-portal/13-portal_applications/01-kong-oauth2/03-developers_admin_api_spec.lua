-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local enums = require "kong.enterprise_edition.dao.enums"
local utils = require "kong.tools.utils"
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

local statuses = enums.CONSUMERS.STATUS


local function configure_portal(db, config)
  config = config or {
    portal = true,
    portal_session_conf = { secret = "super-secret" },
  }

  return db.workspaces:update_by_name("default", {
    name = "default",
    config = config,
  })
end


local function verify_order(data, key, sort_desc)
  for i = 1, #data - 1 do
    local current_val = data[i][key]
    local next_val = data[i + 1][key]

    local current_is_nil = current_val == nil
    local next_is_nil = next_val == nil

    if current_is_nil then
      assert.is_true(not sort_desc or next_is_nil)
    elseif next_is_nil then
      assert.is_true(sort_desc)
    else
      assert.is_true(current_val == next_val or current_val > next_val == sort_desc)
    end
  end
end


for _, strategy in helpers.each_strategy() do
  describe("Admin API - Applications #" .. strategy, function()
    local client
    local db
    local reset_license_data
    lazy_setup(function()

      reset_license_data = clear_license_env()

      _, db = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database = strategy,
        license_path = "spec-ee/fixtures/mock_license.json",
        portal = true,
        portal_and_vitals_key = get_portal_and_vitals_key(),
        portal_app_auth = "kong-oauth2",
        portal_auth = "basic-auth",
        portal_session_conf = "{ \"secret\": \"super-secret\" }",
      }))

      -- these need to be set so that setup and before hooks have the correct conf
      kong.configuration = { portal_auth = "basic-auth",  portal_app_auth = "kong-oauth2" }
      kong.configuration = { portal_auth = "basic-auth",  portal_app_auth = "kong-oauth2" }
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true, true)
      reset_license_data()
    end)

    before_each(function()
      client = assert(helpers.admin_client())
      assert(configure_portal(db))
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("/developers/:developer", function()
      describe("PATCH", function()
        local developer,
              service_one,
              service_two,
              application_one,
              application_two,
              application_instance_one,
              application_instance_two

        before_each(function()
          service_one = assert(db.services:insert({
            name = "service_one",
            url = "http://google.com"
          }))

          service_two = assert(db.services:insert({
            name = "service_two",
            url = "http://google.com"
          }))

          assert(db.plugins:insert({
            config = {
              enable_authorization_code = true,
            },
            name = "oauth2",
            service = { id = service_one.id },
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin one",
            },
            name = "application-registration",
            service = { id = service_one.id },
          }))

          assert(db.plugins:insert({
            config = {
              enable_authorization_code = true,
            },
            name = "oauth2",
            service = { id = service_two.id },
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin one",
            },
            name = "application-registration",
            service = { id = service_two.id },
          }))

          developer = assert(db.developers:insert({
            email = "revoked@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
            status = enums.CONSUMERS.STATUS.REVOKED,
          }))

          application_one = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          application_two = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRntCool",
            redirect_uri = "http://doghouse.com",
          }))

          application_instance_one = assert(db.application_instances:insert({
            application = { id = application_one.id },
            service = { id = service_one.id },
            status = enums.CONSUMERS.STATUS.APPROVED
          }))

          application_instance_two = assert(db.application_instances:insert({
            application = { id = application_two.id },
            service = { id = service_two.id },
            status = enums.CONSUMERS.STATUS.APPROVED
          }))
        end)

        after_each(function()
          db:truncate("services")
          db:truncate("basicauth_credentials")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
          db:truncate("application_instances")
        end)

        it("devs application_instance's are set 'suspended' param correctly based off dev status", function()
          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id,
            body = {
              status = 0,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(200, res)

          local res_one = assert(kong.db.application_instances:select({ id = application_instance_one.id }))
          local res_two = assert(kong.db.application_instances:select({ id = application_instance_two.id }))

          assert.falsy(res_one.suspended)
          assert.falsy(res_two.suspended)

          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id,
            body = {
              status = 1,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(200, res)

          local res_one = assert(kong.db.application_instances:select({ id = application_instance_one.id }))
          local res_two = assert(kong.db.application_instances:select({ id = application_instance_two.id }))

          assert(res_one.suspended)
          assert(res_two.suspended)
        end)

        it("devs application_instance's re-create acl group when status is revoked, then re-introduced", function()
          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id,
            body = {
              status = 0,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(200, res)

          local res_one = assert(kong.db.application_instances:select({ id = application_instance_one.id }))
          local res_two = assert(kong.db.application_instances:select({ id = application_instance_two.id }))
          assert.falsy(res_one.suspended)
          assert.falsy(res_two.suspended)

          for row, err in db.daos["acls"]:each_for_consumer({ id = application_one.consumer.id }) do
            assert.equal(row.group, service_one.id)
          end

          for row, err in db.daos["acls"]:each_for_consumer({ id = application_two.consumer.id }) do
            assert.equal(row.group, service_two.id)
          end


          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id,
            body = {
              status = 1,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(200, res)

          local res_one = assert(kong.db.application_instances:select({ id = application_instance_one.id }))
          local res_two = assert(kong.db.application_instances:select({ id = application_instance_two.id }))
          assert(res_one.suspended)
          assert(res_two.suspended)

          local creds = {}
          for row, err in db.daos["acls"]:each_for_consumer({ id = application_one.consumer.id }) do
            if row then
              table.insert(creds, row)
            end
          end

          assert.equal(#creds, 0)

          creds = {}
          for row, err in db.daos["acls"]:each_for_consumer({ id = application_two.consumer.id }) do
            if row then
              table.insert(creds, row)
            end
          end

          assert.equal(#creds, 0)


          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id,
            body = {
              status = 0,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(200, res)

          local res_one = assert(kong.db.application_instances:select({ id = application_instance_one.id }))
          local res_two = assert(kong.db.application_instances:select({ id = application_instance_two.id }))
          assert.falsy(res_one.suspended)
          assert.falsy(res_two.suspended)

          for row, err in db.daos["acls"]:each_for_consumer({ id = application_one.consumer.id }) do
            assert.equal(row.group, service_one.id)
          end

          for row, err in db.daos["acls"]:each_for_consumer({ id = application_two.consumer.id }) do
            assert.equal(row.group, service_two.id)
          end
        end)
      end)

      describe("DELETE", function()
        local developer, application

        lazy_setup(function()
          local service = assert(db.services:insert({
            name = "service",
            url = "http://google.com"
          }))

          assert(db.plugins:insert({
            config = {
              enable_authorization_code = true,
            },
            name = "oauth2",
            service = { id = service.id },
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin one",
            },
            name = "application-registration",
            service = { id = service.id },
          }))

          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          assert(db.application_instances:insert({
            application = { id = application.id },
            service = { id = service.id },
          }))
        end)

        lazy_teardown(function()
          db:truncate("basicauth_credentials")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
          db:truncate("application_instances")
        end)

        it("developers consumer, as well as its applications are removed when developer is deleted", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)

          assert.is_nil(kong.db.consumers:select({ id = developer.consumer.id }))
          assert.is_nil(kong.db.applications:select({ id = application.id }))
        end)
      end)
    end)

    describe("/developers/:developer/applications", function()
      describe("GET", function()
        local developer_one, developer_two

        lazy_setup(function()
          developer_one = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          assert(db.applications:insert({
            developer = { id = developer_one.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
            description = "weee"
          }))

          assert(db.applications:insert({
            developer = { id = developer_one.id },
            name = "bonesRcool2",
            redirect_uri = "http://doghouse.com",
          }))

          developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "meow",
            meta = '{ "full_name": "bob" }',
          }))

          assert(db.applications:insert({
            developer = { id = developer_two.id },
            name = "catnipIsDope",
            redirect_uri = "http://puur.com",
          }))
        end)

        lazy_teardown(function()
          db:truncate("basicauth_credentials")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can retrieve all applications for single developer", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 2)
          assert.equal(json.data[1].developer.id, developer_one.id)

          res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_two.id .. "/applications",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(json.data[1].developer.id, developer_two.id)
        end)

        it("Paginates properly", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications?size=1",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)

          local res = assert(client:send({
            method = "GET",
            path = json.next,
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(ngx.null, json.next)
        end)

        it("sorts by id ASC by default", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(2, resp_body_json.total)

          verify_order(resp_body_json.data, "id", false)
        end)

        it("sorts by id DESC with 'sort_desc=true' param", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications?sort_desc=true",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(2, resp_body_json.total)

          verify_order(resp_body_json.data, "id", true)
        end)

        it("sorts by name ASC with 'sort_by=name' param", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications?sort_by=name",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(2, resp_body_json.total)

          verify_order(resp_body_json.data, "name", false)
        end)

        it("sorts by name DESC with 'sort_by=name&sort_desc=true' param", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications?sort_by=name&sort_desc=true",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(2, resp_body_json.total)

          verify_order(resp_body_json.data, "name", true)
        end)

        it("sorts by id ASC if sort_by values are the same", function ()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications?sort_by=redirect_uri",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(2, resp_body_json.total)

          verify_order(resp_body_json.data, "id", false)
        end)

        it("sorts by id DESC if sort_by values are the same", function ()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications?sort_by=redirect_uri&sort_desc=true",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(2, resp_body_json.total)

          verify_order(resp_body_json.data, "id", true)
        end)

        it("handles nil values when sorting ASC", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications?sort_by=description",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(2, resp_body_json.total)

          verify_order(resp_body_json.data, "description", false)
        end)

        it("handles nil values when sorting DESC", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications?sort_by=description&sort_desc=true",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(2, resp_body_json.total)

          verify_order(resp_body_json.data, "description", true)
        end)

        it("maintains sort across pages ASC", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications?sort_by=name&size=1",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(1, resp_body_json.total)

          verify_order(resp_body_json.data, "name", false)

          local last_name_first_page = resp_body_json.data[#resp_body_json.data]

          local res = assert(client:send {
            method = "GET",
            path = resp_body_json.next,
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(1, resp_body_json.total)

          verify_order(resp_body_json.data, "name", false)

          local first_name_second_page = resp_body_json.data[1]

          verify_order({last_name_first_page, first_name_second_page}, "name", false)
        end)

        it("maintains sort across pages DESC", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications?sort_by=name&size=1&sort_desc=true",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(1, resp_body_json.total)

          verify_order(resp_body_json.data, "name", true)

          local last_name_first_page = resp_body_json.data[#resp_body_json.data]

          local res = assert(client:send {
            method = "GET",
            path = resp_body_json.next,
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.equal(1, resp_body_json.total)

          verify_order(resp_body_json.data, "name", true)

          local first_name_second_page = resp_body_json.data[1]

          verify_order({last_name_first_page, first_name_second_page}, "name", true)
        end)
      end)

      describe("POST", function()
        local developer_one, developer_two, app_one

        before_each(function()
          developer_one = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "meow",
            meta = '{ "full_name": "bob" }',
          }))

          app_one = assert(db.applications:insert({
            developer = { id = developer_one.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          assert(db.applications:insert({
            developer = { id = developer_two.id },
            name = "catnipIsDope",
            redirect_uri = "http://puur.com",
          }))
        end)

        after_each(function()
          db:truncate("basicauth_credentials")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can create an applications", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_one.id .. "/applications",
            body = {
              name = "coolapp",
              redirect_uri = "http://coolapp.com",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.equal(json.developer.id, developer_one.id)
          assert.equal(json.name, "coolapp")
          assert.equal(json.redirect_uri, "http://coolapp.com")
        end)


        it("can create application with same name as another devs application", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_two.id .. "/applications",
            body = {
              name = app_one.name,
              redirect_uri = app_one.redirect_uri,
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.equal(json.developer.id, developer_two.id)
          assert.equal(json.name, app_one.name)
          assert.equal(json.redirect_uri, app_one.redirect_uri)
        end)

        it("creates a consumer alongside the application", function()
          assert.is_nil(db.consumers:select_by_username(developer_one.id .. "_coolapp"))

          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_one.id .. "/applications",
            body = {
              name = "coolapp",
              redirect_uri = "http://coolapp.com",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(201, res)
          assert(db.consumers:select_by_username(developer_one.id .. "_coolapp"))
        end)

        it("ignores developer in body", function()
          assert.is_nil(db.consumers:select_by_username(developer_one.id .. "_new_app"))
          assert.is_nil(db.consumers:select_by_username(developer_two.id .. "_new_app"))

          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_one.id .. "/applications",
            body = {
              name = "new_app",
              developer = { id = developer_two.id },
              redirect_uri = "http://coolapp.com",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.equal(developer_one.id, json.developer.id)
          assert(db.consumers:select_by_username(developer_one.id .. "_new_app"))
          assert.is_nil(db.consumers:select_by_username(developer_two.id .. "_new_app"))
        end)

        it("cannot create an application with missing name", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_one.id .. "/applications",
            body = {
              redirect_uri = "http://coolapp.com",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.name, "required field missing")
        end)

        it("cannot create an application with missing redirect_uri", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_one.id .. "/applications",
            body = {
              name = "coolapp",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.redirect_uri, "required field missing")
        end)

        it("cannot create an application with the same name for the same developer", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_one.id .. "/applications",
            body = {
              name = app_one.name,
              redirect_uri = app_one.redirect_uri,
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(409, res)
        end)
      end)
    end)

    describe("/developers/:developer/applications/:application", function()
      local developer_one, developer_two, app_one, app_two

      describe("GET", function()
        lazy_setup(function()
          developer_one = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "meow",
            meta = '{ "full_name": "bob" }',
          }))

          app_one = assert(db.applications:insert({
            developer = { id = developer_one.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          app_two = assert(db.applications:insert({
            developer = { id = developer_two.id },
            name = "catnipIsDope",
            redirect_uri = "http://puur.com",
          }))
        end)

        lazy_teardown(function()
          db:truncate("basicauth_credentials")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can retrieve an application", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(json.id, app_one.id)

          res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_two.id .. "/applications/" .. app_two.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          body = assert.res_status(200, res)
          json = cjson.decode(body)

          assert.equal(json.id, app_two.id)
        end)

        it("cannot retrieve an application with wrong developer", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_two.id .. "/applications/" .. app_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)
        end)

        it("returns error with improper primary key", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications/a",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.id, "expected a valid UUID")
        end)
      end)

      describe("PATCH", function()
        before_each(function()
          developer_one = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "meow",
            meta = '{ "full_name": "bob" }',
          }))

          app_one = assert(db.applications:insert({
            developer = { id = developer_one.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          app_two = assert(db.applications:insert({
            developer = { id = developer_two.id },
            name = "catnipIsDope",
            redirect_uri = "http://puur.com",
          }))
        end)

        after_each(function()
          db:truncate("basicauth_credentials")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("updates consumer username when 'name' is updated", function()
          local new_name = "new_app_woah_cool"
          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_one.id,
            body = {
              name = new_name,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(200, res.status)

          local consumer = assert(kong.db.consumers:select({ id = app_one.consumer.id }))
          assert.equal(consumer.username, developer_one.id .. "_" .. new_name)
        end)

        it("cannot update application with wrong developer", function()
          local new_name = "new_app_woah_cool"
          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer_two.id .. "/applications/" .. app_one.id,
            body = {
              name = new_name,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(404, res.status)
        end)

        it("ignores developer in body", function()
          assert.is_nil(db.consumers:select_by_username(developer_one.id .. "_new_app"))
          assert.is_nil(db.consumers:select_by_username(developer_two.id .. "_new_app"))

          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_one.id,
            body = {
              name = "new_app",
              developer = { id = developer_two.id },
              redirect_uri = "http://coolapp.com",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(developer_one.id, json.developer.id)
          assert(db.consumers:select_by_username(developer_one.id .. "_new_app"))
          assert.is_nil(db.consumers:select_by_username(developer_two.id .. "_new_app"))
        end)

        it("updates oauth2 credentials when 'name' updated", function()
          local new_name = "new_app_woah_cool"
          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_one.id,
            body = {
              name = new_name,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(200, res.status)

          for row, err in db.daos["oauth2_credentials"]:each_for_consumer({ id = app_one.consumer.id }) do
            if row then
              assert.equal(row.name, new_name)
            end
          end
        end)

        it("updates oauth2 credentials when 'redirect_uri' updated", function()
          local new_uri = "http://dog.com"
          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_one.id,
            body = {
              redirect_uri = new_uri,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(200, res.status)

          for row, err in db.daos["oauth2_credentials"]:each_for_consumer({ id = app_one.consumer.id }) do
            if row then
              assert.equal(row.redirect_uris[1], new_uri)
            end
          end
        end)
      end)

      describe("DELETE", function()
        local developer_one, developer_two, app_one

        before_each(function()
          developer_one = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          app_one = assert(db.applications:insert({
            developer = { id = developer_one.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "puur",
            meta = '{ "full_name": "bob" }',
          }))

          assert(db.applications:insert({
            developer = { id = developer_two.id },
            name = "bonesRcool2",
            redirect_uri = "http://doghouse.com",
          }))
        end)

        after_each(function()
          db:truncate("basicauth_credentials")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("delete cascades to applications related entities", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(204, res.status)

          res = db.application_instances:select({ id = app_one.id })
          assert.is_nil(res)

          res = db.consumers:select({ id = app_one.consumer.id })
          assert.is_nil(res)

          local creds = {}
          for row, err in db.daos["oauth2_credentials"]:each_for_consumer({ id = app_one.consumer.id }) do
            if row then
              table.insert(creds, row)
            end
          end

          assert.is_nil(next(creds))
        end)

        it("cannot delete application given wrong developer", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_two.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(404, res.status)
        end)

        it("can create an application with the same name after deletion", function()
          assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))

          assert(db.applications:insert({
            developer = { id = developer_one.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))
        end)
      end)
    end)

    describe("/developers/:developer/applications/:applications/credentials/:plugin", function()
      describe("GET", function()
        local developer_one, developer_two, app_one, app_two

        lazy_setup(function()
          developer_one = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "puur",
            meta = '{ "full_name": "bob" }',
          }))

          app_one = assert(db.applications:insert({
            developer = { id = developer_one.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          app_two = assert(db.applications:insert({
            developer = { id = developer_two.id },
            name = "bonesRcool2",
            redirect_uri = "http://doghouse.com",
          }))
        end)

        lazy_teardown(function()
          db:truncate("basicauth_credentials")
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can retrieve oauth2 creds attached to an application", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_one.id .. "/credentials/oauth2",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(json.data[1].consumer.id, app_one.consumer.id)
        end)

        it("does not retrieve oauth2 creds attached to a different app", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_two.id .. "/credentials/oauth2",
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)
        end)

        it("does not retrieve creds of a different auth type", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_two.id .. "/credentials/keyauth",
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)
        end)
      end)

      describe("POST", function()
        local developer_one, developer_two, app_one, app_two

        before_each(function()
          developer_one = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "puur",
            meta = '{ "full_name": "bob" }',
          }))

          app_one = assert(db.applications:insert({
            developer = { id = developer_one.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          app_two = assert(db.applications:insert({
            developer = { id = developer_two.id },
            name = "bonesRcool2",
            redirect_uri = "http://doghouse.com",
          }))
        end)

        after_each(function()
          db:truncate("basicauth_credentials")
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can create a new credential set", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_one.id .. "/credentials/oauth2",
            body = {},
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          local key_auth_cred_created = false

          for row, err in db.daos["keyauth_credentials"]:each_for_consumer({ id = app_one.consumer.id }) do
            if row.key == json.client_id then
              key_auth_cred_created = true
            end
          end

          assert.is_true(key_auth_cred_created)
        end)

        it("cannot create a new credential set for wrong app", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_two.id .. "/credentials/oauth2",
            body = {},
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)
        end)

        it("cannot set any attributes in created entity", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_one.id .. "/applications/" .. app_one.id ..  "/credentials/oauth2",
            body = {
              consumer = { id = utils.uuid() },
              name = "coolAppYo",
              redirect_uris = { "http://dog.com" },
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.equal(json.name, app_one.name)
          assert.equal(json.consumer.id, app_one.consumer.id)
          assert.equal(json.redirect_uris[1], app_one.redirect_uri)
        end)
      end)
    end)

    describe("/developers/:developer/applications/:applications/credentials/:plugin/:credential", function()
      describe("GET", function()
        local developer, application, application_two

        lazy_setup(function()
          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          application_two = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool2",
            redirect_uri = "http://doghouse.com",
          }))
        end)

        lazy_teardown(function()
          db:truncate("basicauth_credentials")
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can retrieve oauth2 creds attached to an application", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/credentials/oauth2",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          local cred = json.data[1]

          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/credentials/oauth2/" .. cred.id,
            headers = {["Content-Type"] = "application/json"}
          }))

          body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(json.id, cred.id)
        end)

        it("does not retrieve oauth2 creds attached to a different app", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/credentials/oauth2",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          local cred = json.data[1]

          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application_two.id .. "/credentials/oauth2/" .. cred.id,
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(404, res)
        end)

        it("does not retrieve creds of a different auth type", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/credentials/keyauth/" .. utils.uuid(),
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        lazy_teardown(function()
          db:truncate("basicauth_credentials")
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("cannot patch a oauth cred", function()
          local developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          local application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/credentials/oauth2/" .. utils.uuid(),
            body = {},
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(405, res)
        end)
      end)

      describe("DELETE", function()
        local developer, application, application_two, cred

        before_each(function()
          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          local creds = {}
          for row, err in db.daos["oauth2_credentials"]:each_for_consumer({ id = application.consumer.id }) do
            if row then
              table.insert(creds, row)
            end
          end

          cred = creds[1]

          application_two = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool2",
            redirect_uri = "http://doghouse.com",
          }))
        end)

        after_each(function()
          db:truncate("basicauth_credentials")
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can delete credential for application", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/credentials/oauth2/" .. cred.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)

          assert.is_nil(db.daos["oauth2_credentials"]:select({ id = cred.id }))

          local key_auth_cred_deleted = true

          for row, err in db.daos["keyauth_credentials"]:each_for_consumer({ id = application.consumer.id }) do
            if row.key == cred.client_id then
              key_auth_cred_deleted = false
            end
          end

          assert.is_true(key_auth_cred_deleted)
        end)

        it("cannot delete credential when wrong developer is set", function()
          local developer_two = assert(db.developers:insert({
            email = "dog2@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer_two.id .. "/applications/" .. application_two.id .. "/credentials/oauth2/" .. cred.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)

          assert(db.daos["oauth2_credentials"]:select({ id = cred.id }))
        end)

        it("cannot delete credential when wrong application is set", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer.id .. "/applications/" .. application_two.id .. "/credentials/oauth2/" .. cred.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)

          assert(db.daos["oauth2_credentials"]:select({ id = cred.id }))
        end)

        it("always returns 204 if uuid is wrong", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer.id .. "/applications/" .. application_two.id .. "/credentials/oauth2/" .. utils.uuid(),
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)
        end)
      end)
    end)

    describe("/developers/:developer/applications/:application/application_instances", function()
      local developer,
            developer_two,
            application_one,
            application_two,
            application_three,
            application_instance_one,
            application_instance_two,
            service_one,
            service_two,
            service_three

      describe("GET", function()
        lazy_setup(function()
          service_one = assert(db.services:insert({
            name = "service_one",
            url = "http://google.com"
          }))

          service_two = assert(db.services:insert({
            name = "service_two",
            url = "http://google.com"
          }))

          service_three = assert(db.services:insert({
            name = "service_three",
            url = "http://google.com"
          }))

          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "puur",
            meta = '{ "full_name": "bob" }',
          }))

          assert(db.plugins:insert({
            config = {
              enable_authorization_code = true,
            },
            name = "oauth2",
            service = { id = service_one.id },
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin one",
            },
            name = "application-registration",
            service = { id = service_one.id },
          }))

          assert(db.plugins:insert({
            config = {
              enable_authorization_code = true,
            },
            name = "oauth2",
            service = { id = service_two.id },
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin two",
            },
            name = "application-registration",
            service = { id = service_two.id },
          }))

          assert(db.plugins:insert({
            config = {
              enable_authorization_code = true,
            },
            name = "oauth2",
            service = { id = service_three.id },
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin three",
            },
            name = "application-registration",
            service = { id = service_three.id },
          }))

          application_one = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          application_instance_one = assert(db.application_instances:insert({
            application = { id = application_one.id },
            service = { id = service_one.id },
          }))

          application_two = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "catnipIsRad",
            redirect_uri = "http://meow.com",
          }))

          application_instance_two = assert(db.application_instances:insert({
            application = { id = application_two.id },
            service = { id = service_one.id },
          }))

          application_three = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "cherpcherp",
            redirect_uri = "http://birds.com",
          }))

          assert(db.application_instances:insert({
            application = { id = application_three.id },
            service = { id = service_one.id },
          }))

          assert(db.application_instances:insert({
            application = { id = application_three.id },
            service = { id = service_two.id },
          }))

          assert(db.application_instances:insert({
            application = { id = application_three.id },
            service = { id = service_three.id },
          }))
        end)

        lazy_teardown(function()
          db:truncate("basicauth_credentials")
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
          db:truncate("application_instances")
        end)

        it("can retrieve application instances", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application_one.id .. "/application_instances",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(json.data[1].id, application_instance_one.id)

          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application_two.id .. "/application_instances",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(json.data[1].id, application_instance_two.id)
        end)

        it("cannot retrieve instance with wrong developer", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_two.id .. "/applications/" .. application_one.id .. "/application_instances",
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(404, res)
        end)

        it("Paginates properly", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application_three.id .. "/application_instances?size=1",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(1, json.total)

          local res = assert(client:send({
            method = "GET",
            path = json.next,
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(1, json.total)

          local res = assert(client:send({
            method = "GET",
            path = json.next,
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(1, json.total)
          assert.equal(ngx.null, json.next)
        end)
      end)

      describe("POST", function()
        local service, developer, application, plugin

        before_each(function()
          service = assert(db.services:insert({
            name = "service",
            url = "http://google.com"
          }))

          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          assert(db.plugins:insert({
            config = {
              enable_authorization_code = true,
            },
            name = "oauth2",
            service = { id = service.id },
          }))

          plugin = assert(db.plugins:insert({
            config = {
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service.id },
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))
        end)

        after_each(function()
          db:truncate("basicauth_credentials")
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can create an application instance", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances",
            body = {
              service = { id = service.id },
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(201, res)
        end)

        it("has status of 'suspended' with non-approved developer", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances",
            body = {
              service = { id = service.id },
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.truthy(json.suspended)
        end)

        it("has status of not 'suspended' with approved developer", function()
          assert(db.developers:update(
            { id = developer.id },
            { status = enums.CONSUMERS.STATUS.APPROVED }
          ))

          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances",
            body = {
              service = { id = service.id },
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.falsy(json.suspended)
        end)

        it("cannot create an application instance with wrong developer", function()
          local developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "puur",
            meta = '{ "full_name": "bob" }',
          }))

          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer_two.id .. "/applications/" .. application.id .. "/application_instances",
            body = {
              service = { id = service.id },
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(404, res)
        end)

        it("cannot create an application instance without service", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances",
            body = {},
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.service, "required field missing")
        end)

        it("errors if invalid service id sent", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances",
            body = {
              service = { id = "abcd" },
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.service.id, "expected a valid UUID")
        end)

        it("can set custom status", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances",
            body = {
              service = { id = service.id },
              status = 2,
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.equal(json.status, 2)
        end)

        it("cannot set invalid status", function()
          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances",
            body = {
              service = { id = service.id },
              status = 10,
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.status, "value should be between 0 and 5")
        end)

        it("status is set to 'approved' when config.auto_approve = true", function()
          assert(db.plugins:update({ id = plugin.id }, {
            config = { auto_approve = true }
          }))

          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances",
            body = {
              service = { id = service.id },
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.equal(statuses.APPROVED, json.status)
        end)

        it("status is set to 'pending' when config.auto_approve = false", function()
          assert(db.plugins:update({ id = plugin.id }, {
            config = { auto_approve = false }
          }))

          local res = assert(client:send({
            method = "POST",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances",
            body = {
              service = { id = service.id },
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.equal(statuses.PENDING, json.status)
        end)
      end)
    end)

    describe("/developers/:developers/applications/:application/application_instances/:application_instances", function()
      local service,
            developer,
            application_one,
            application_two,
            application_instance_one,
            application_instance_two

      describe("GET", function()
        lazy_setup(function()
          service = assert(db.services:insert({
            name = "service",
            url = "http://google.com"
          }))

          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          assert(db.plugins:insert({
            config = {
              enable_authorization_code = true,
            },
            name = "oauth2",
            service = { id = service.id },
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service.id },
          }))

          application_one = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          application_two = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool2",
            redirect_uri = "http://doghouse.com",
          }))

          application_instance_one = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application_one.id },
            status = 4,
          }))

          application_instance_two = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application_two.id },
            status = 4,
          }))
        end)


        lazy_teardown(function()
          db:truncate("basicauth_credentials")
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
          db:truncate("application_instances")
        end)


        it("can retrieve application_instance", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application_one.id .. "/application_instances/" .. application_instance_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(json.id, application_instance_one.id)

          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application_two.id .. "/application_instances/" .. application_instance_two.id,
            headers = {["Content-Type"] = "application/json"}
          }))

          body = assert.res_status(200, res)
          json = cjson.decode(body)

          assert.equal(json.id, application_instance_two.id)
        end)

        it("cannot retrieve application_instance with wrong developer id", function()
          local developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "puur",
            meta = '{ "full_name": "bob" }',
          }))

          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_two.id .. "/applications/" .. application_one.id .. "/application_instances/" .. application_instance_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)

          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer_two.id .. "/applications/" .. application_two.id .. "/application_instances/" .. application_instance_two.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)
        end)

        it("cannot retrieve application_instance with wrong application id", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application_two.id .. "/application_instances/" .. application_instance_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)

          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application_one.id .. "/application_instances/" .. application_instance_two.id,
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(404, res)
        end)

        it("returns 400 if application_id is invalid", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/ohnothisisnotright/application_instances/" .. application_instance_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.id, "expected a valid UUID")
        end)

        it("returns 400 if application_instance_id is invalid", function()
          local res = assert(client:send({
            method = "GET",
            path = "/developers/" .. developer.id .. "/applications/" .. application_one.id .. "/application_instances/asdfasdf",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.id, "expected a valid UUID")
        end)
      end)

      describe("PATCH", function()
        local application, service, developer

        before_each(function()
          service = assert(db.services:insert({
            name = "service",
            url = "http://google.com"
          }))

          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
            status = enums.CONSUMERS.STATUS.APPROVED,
          }))

          assert(db.plugins:insert({
            config = {
              enable_authorization_code = true,
            },
            name = "oauth2",
            service = { id = service.id },
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service.id },
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))
        end)

        after_each(function()
          db:truncate("basicauth_credentials")
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
          db:truncate("application_instances")
        end)

        it("cannot patch application_instance with wrong developer id", function()
          local developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "puur",
            meta = '{ "full_name": "bob" }',
          }))

          local application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id },
            status = 0,
          }))

          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer_two.id .. "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
            body = {
              status = 1,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)
        end)

        it("can patch status", function()
          local application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id },
            status = 0,
          }))

          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
            body = {
              status = 1,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(json.status, 1)
        end)

        it("cannot patch to invalid status", function()
          local application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id },
            status = 0,
          }))

          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
            body = {
              status = 10,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.status, "value should be between 0 and 5")
        end)

        it("cant patch referenced entities", function()
          local service_two = assert(db.services:insert({
            name = "service2",
            url = "http://google.com"
          }))

          local application_two = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool2",
            redirect_uri = "http://doghouse.com",
          }))

          local application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id },
            status = 0,
          }))

          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
            body = {
              service = { id = service_two.id},
              application = { id = application_two.id },
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(200, res)

          res = assert(db.application_instances:select({ id = application_instance.id }))

          assert.equal(res.service.id, service.id)
          assert.equal(res.application.id, application.id)
        end)

        it("ACL group is added when status is set to 'approved'", function()
          local application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id },
            status = 4,
          }))

          local creds = {}
          for row, err in db.daos["acls"]:each_for_consumer({ id = application.consumer.id }) do
            if row then table.insert(creds, row) end
          end

          assert.equal(#creds, 0)

          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
            body = {
              status = 0,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(200, res.status)

          creds = {}
          for row, err in db.daos["acls"]:each_for_consumer({ id = application.consumer.id }) do
            if row then table.insert(creds, row) end
          end

          assert.equal(#creds, 1)
        end)

        it("ACL group removed when status is set to 'revoked'", function()
          local application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id },
            status = 0,
          }))

          local creds = {}
          for row, err in db.daos["acls"]:each_for_consumer({ id = application.consumer.id }) do
            if row then table.insert(creds, row) end
          end

          assert.equal(#creds, 1)

          local res = assert(client:send({
            method = "PATCH",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
            body = {
              status = 4,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(200, res.status)

          creds = {}
          for row, err in db.daos["acls"]:each_for_consumer({ id = application.consumer.id }) do
            if row then table.insert(creds, row) end
          end

          assert.equal(#creds, 0)
        end)
      end)

      describe("DELETE", function()
        local application_instance, service, developer, application

        before_each(function()
          service = assert(db.services:insert({
            name = "service",
            url = "http://google.com"
          }))

          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          assert(db.plugins:insert({
            config = {
              enable_authorization_code = true,
            },
            name = "oauth2",
            service = { id = service.id },
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service.id },
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            redirect_uri = "http://doghouse.com",
          }))

          application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id },
            status = statuses.APPROVED,
          }))
        end)

        after_each(function()
          db:truncate("basicauth_credentials")
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
          db:truncate("application_instances")
        end)

        it("can delete existing application_instance", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)

          local application_instance, err, err_t = db.application_instances:select({ id = application_instance.id })

          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.is_nil(application_instance)
        end)

        it("cannot delete existing application_instance with wrong developer", function()
          local developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "puur",
            meta = '{ "full_name": "bob" }',
          }))

          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer_two.id .. "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)

          assert(db.application_instances:select({ id = application_instance.id }))
        end)

        it("deletes ACL group when application_instance is removed", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)

          local creds = {}
          for row, err in db.daos["acls"]:each_for_consumer({ id = application.consumer.id }) do
            if row then table.insert(creds, row) end
          end

          assert.equal(#creds, 0)
        end)

        it("returns 204 when application_instance does not exist", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/developers/" .. developer.id .. "/applications/" .. application.id .. "/application_instances/" .. utils.uuid(),
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)
        end)
      end)
    end)
  end)
end
