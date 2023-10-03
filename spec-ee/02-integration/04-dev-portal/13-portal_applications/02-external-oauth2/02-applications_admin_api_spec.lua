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

for _, strategy in helpers.each_strategy() do
  describe("Admin API - Applications #" .. strategy, function()
    local client
    local db

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database = strategy,
        portal = true,
        portal_app_auth = "external-oauth2",
        portal_auth = "basic-auth",
        portal_session_conf = "{ \"secret\": \"super-secret\" }",
      }))

      -- these need to be set so that setup and before hooks have the correct conf
      kong.configuration = { portal_auth = "basic-auth",  portal_app_auth = "external-oauth2"}
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true, true)
    end)

    before_each(function()
      client = assert(helpers.admin_client())
      assert(configure_portal(db))
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("/applications", function()
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
            custom_id = "doggo",
          }))

          developer_two = assert(db.developers:insert({
            email = "cat@meow.com",
            password = "meow",
            meta = '{ "full_name": "bob" }',
          }))

          assert(db.applications:insert({
            developer = { id = developer_two.id },
            name = "catnipIsDope",
            custom_id = "catto",
          }))
        end)

        lazy_teardown(function()
          db:truncate('basicauth_credentials')
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can retrieve all applications across developers", function()
          local res = assert(client:send({
            method = "GET",
            path = "/applications",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 2)
        end)

        it("paginates properly", function()
          local res = assert(client:send({
            method = "GET",
            path = "/applications?size=1",
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)

          local res = assert(client:send({
            method = "GET",
            path = "/applications",
            query = { offset = json.offset, size = 1 },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(ngx.null, json.next)
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
            custom_id = "doggo",
          }))

          assert(db.applications:insert({
            developer = { id = developer_two.id },
            name = "catnipIsDope",
            custom_id = "catto",
          }))
        end)

        after_each(function()
          db:truncate('basicauth_credentials')
          db:truncate("applications")
          db:truncate("developers")
          db:truncate("consumers")
        end)

        it("can create an applications", function()
          local res = assert(client:send({
            method = "POST",
            path = "/applications",
            body = {
              developer = { id = developer_one.id },
              name = "coolapp",
              custom_id = "coolboi",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.equal(json.developer.id, developer_one.id)
          assert.equal(json.name, "coolapp")
          assert.equal(json.custom_id, "coolboi")
        end)


        it("can create application with same name as another devs application", function()
          local res = assert(client:send({
            method = "POST",
            path = "/applications",
            body = {
              developer = { id = developer_two.id },
              name = app_one.name,
              custom_id = "custom",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.equal(json.developer.id, developer_two.id)
          assert.equal(json.name, app_one.name)
        end)

        it("creates a consumer alongside the application", function()
          assert.is_nil(db.consumers:select_by_username(developer_one.id .. "_coolapp"))

          local res = assert(client:send({
            method = "POST",
            path = "/applications",
            body = {
              developer = { id = developer_one.id },
              name = "coolapp",
              custom_id = "coolboi",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(201, res)
          local consumer = assert(db.consumers:select_by_username(developer_one.id .. "_coolapp"))
          assert("coolboi", consumer.custom_id)
        end)

        it("cannot create an application with missing name", function()
          local res = assert(client:send({
            method = "POST",
            path = "/applications",
            body = {
              developer = { id = developer_one.id },
              custom_id = "coolboi",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.name, "required field missing")
        end)

        it("cannot create an application with missing developer", function()
          local res = assert(client:send({
            method = "POST",
            path = "/applications",
            body = {
              name = "coolapp",
              custom_id = "coolboi",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.developer, "required field missing")
        end)

        it("cannot create an application with missing custom_id", function()
          local res = assert(client:send({
            method = "POST",
            path = "/applications",
            body = {
              developer = { id = developer_one.id },
              name = "coolapp",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.custom_id, "required field missing")
        end)

        it("cannot create an application with the same name for the same developer", function()
          local res = assert(client:send({
            method = "POST",
            path = "/applications",
            body = {
              developer = { id = developer_one.id },
              name = app_one.name,
              custom_id = "custom_two",
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(409, res)
        end)

        it("cannot create an application with the same custom_id as another app", function()
          local res = assert(client:send({
            method = "POST",
            path = "/applications",
            body = {
              developer = { id = developer_one.id },
              name = "different name",
              custom_id = app_one.custom_id,
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(409, res)
        end)
      end)
    end)

    describe("/applications/:application", function()
      local application, developer, application_instance

      describe("GET", function()
        lazy_setup(function()
          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            custom_id = "doggo",
          }))
        end)

        lazy_teardown(function()
          db:truncate('basicauth_credentials')
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can retrieve an application", function()
          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(json.id, application.id)
        end)

        it("returns error with improper primary key", function()
          local res = assert(client:send({
            method = "GET",
            path = "/applications/dogsrcool",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.id, "expected a valid UUID")
        end)
      end)

      describe("PATCH", function()
        local application_2

        before_each(function()
          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            custom_id = "doggo",
          }))

          application_2 = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "app2",
            custom_id = "doggo_2",
          }))

          local service = assert(db.services:insert({
            name = "service",
            url = "http://google.com"
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service.id },
          }))

          application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id }
          }))
        end)

        after_each(function()
          db:truncate('basicauth_credentials')
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("updates consumer username when 'name' is updated", function()
          local new_name = "new_app_woah_cool"
          local res = assert(client:send({
            method = "PATCH",
            path = "/applications/" .. application.id,
            body = {
              name = new_name,
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(200, res.status)

          local consumer = assert(kong.db.consumers:select({ id = application.consumer.id }))

          assert.equal(consumer.username, developer.id .. "_" .. new_name)
        end)

        it("updates consumer custom_id when 'custom_id' is updated", function()
          local res = assert(client:send({
            method = "PATCH",
            path = "/applications/" .. application.id,
            body = {
              custom_id = "supersweet",
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(200, res.status)

          local consumer = assert(kong.db.consumers:select({ id = application.consumer.id }))

          assert.equal(consumer.custom_id, "supersweet")
        end)

        it("cannot update application with null custom_id", function()
          local res = assert(client:send({
            method = "PATCH",
            path = "/applications/" .. application.id,
            body = {
              custom_id = ngx.null,
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(400, res)
          local resp_body_json = cjson.decode(body)

          assert.equal("required field missing", resp_body_json.fields.custom_id)
        end)

        it("cannot update application with duplicate custom_id", function()
          local res = assert(client:send({
            method = "PATCH",
            path = "/applications/" .. application.id,
            body = {
              custom_id = application_2.custom_id,
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(409, res)
          local resp_body_json = cjson.decode(body)

          assert.equal("application already exists with custom_id: 'doggo_2'", resp_body_json.fields.custom_id)
        end)

        it("cannot update application with duplicate name", function()
          local res = assert(client:send({
            method = "PATCH",
            path = "/applications/" .. application.id,
            body = {
              name = application_2.name,
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          local body = assert.res_status(409, res)
          local resp_body_json = cjson.decode(body)

          assert.equal("application already exists with name: 'app2'", resp_body_json.fields.name)
        end)
      end)

      describe("DELETE", function()
        before_each(function()
          developer = assert(db.developers:insert({
            email = "bob@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            custom_id = "doggo",
          }))

          local service = assert(db.services:insert({
            name = "service",
            url = "http://google.com"
          }))

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service.id },
          }))

          application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id }
          }))
        end)

        after_each(function()
          db:truncate('basicauth_credentials')
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("delete cascades to applications related entities", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/applications/" .. application.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.equal(204, res.status)

          res = db.application_instances:select({ id = application_instance.id })
          assert.is_nil(res)

          res = db.consumers:select({ id = application.consumer.id })
          assert.is_nil(res)
        end)

        it("can create an application with the same name after deletion", function()
          assert(client:send({
            method = "DELETE",
            path = "/applications/" .. application.id,
            headers = {["Content-Type"] = "application/json"}
          }))

          assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            custom_id = "doggo",
          }))
        end)
      end)
    end)

    describe("/applications/:applications/credentials/:plugin", function()
      describe("GET", function()
        local developer, application

        lazy_setup(function()
          developer = assert(db.developers:insert({
            email = "bob@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            custom_id = "super_duper",
          }))
        end)

        lazy_teardown(function()
          db:truncate('basicauth_credentials')
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("returns 404", function()
          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application.id .. "/credentials/oauth2",
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(404, res)
        end)
      end)

      describe("POST", function()
        local developer, application

        before_each(function()
          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            custom_id = "woof",
          }))
        end)

        after_each(function()
          db:truncate('basicauth_credentials')
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("returns 404", function()
          local res = assert(client:send({
            method = "POST",
            path = "/applications/" .. application.id .. "/credentials/oauth2",
            body = {},
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)
        end)
      end)
    end)

    describe("/applications/:application/application_instances", function()
      local developer,
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

          assert(db.plugins:insert({
            config = {
              display_name = "dope plugin one",
            },
            name = "application-registration",
            service = { id = service_one.id },
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
              display_name = "dope plugin three",
            },
            name = "application-registration",
            service = { id = service_three.id },
          }))

          application_one = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            custom_id = "doggo",
          }))

          application_instance_one = assert(db.application_instances:insert({
            application = { id = application_one.id },
            service = { id = service_one.id },
          }))

          application_two = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "catnipIsRad",
            custom_id = "catto",
          }))

          application_instance_two = assert(db.application_instances:insert({
            application = { id = application_two.id },
            service = { id = service_one.id },
          }))

          application_three = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "cherpcherp",
            custom_id = "birb",
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
          db:truncate('basicauth_credentials')
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can retrieve application instances", function()
          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application_one.id .. "/application_instances",
            headers = { ["Content-Type"] = "application/json" }
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(json.data[1].id, application_instance_one.id)
          assert.equal(json.data[1].service.display_name, "dope plugin one")

          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application_two.id .. "/application_instances",
            headers = { ["Content-Type"] = "application/json" }
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(json.data[1].id, application_instance_two.id)
          assert.equal(json.data[1].service.display_name, "dope plugin one")
        end)

        it("paginates properly", function()
          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application_three.id .. "/application_instances?size=1",
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
            custom_id = "doggo",
          }))
        end)

        after_each(function()
          db:truncate('basicauth_credentials')
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can create an application instance", function()
          local res = assert(client:send({
            method = "POST",
            path = "/applications/" .. application.id .. "/application_instances",
            body = {
              service = { id = service.id },
            },
            headers = {["Content-Type"] = "application/json"}
          }))

          assert.res_status(201, res)
        end)

        it("cannot create an application instance without service", function()
          local res = assert(client:send({
            method = "POST",
            path = "/applications/" .. application.id .. "/application_instances",
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
            path = "/applications/" .. application.id .. "/application_instances",
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
            path = "/applications/" .. application.id .. "/application_instances",
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
            path = "/applications/" .. application.id .. "/application_instances",
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
            path = "/applications/" .. application.id .. "/application_instances",
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
            path = "/applications/" .. application.id .. "/application_instances",
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

    describe("/applications/:application/application_instances/:application_instances", function()
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
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service.id },
          }))

          application_one = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            custom_id = "doggo",
          }))

          application_two = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool2",
            custom_id = "doggo2",
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
          db:truncate('basicauth_credentials')
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)


        it("can retrieve application_instance", function()
          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application_one.id .. "/application_instances/" .. application_instance_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(json.id, application_instance_one.id)

          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application_two.id .. "/application_instances/" .. application_instance_two.id,
            headers = {["Content-Type"] = "application/json"}
          }))

          body = assert.res_status(200, res)
          json = cjson.decode(body)

          assert.equal(json.id, application_instance_two.id)
        end)

        it("cannot retrieve application_instance with wrong application id", function()
          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application_two.id .. "/application_instances/" .. application_instance_one.id,
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
            path = "/applications/ohnothisisnotright/application_instances/" .. application_instance_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.id, "expected a valid UUID")
        end)

        it("returns 400 if application_instance_id is invalid", function()
          local res = assert(client:send({
            method = "GET",
            path = "/applications/" .. application_one.id .. "/application_instances/asdfasdf",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equal(json.fields.id, "expected a valid UUID")
        end)
      end)

      describe("PATCH", function()
        local application

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
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service.id },
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            custom_id = "doggo",
          }))
        end)

        after_each(function()
          db:truncate('basicauth_credentials')
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can patch status", function()
          local application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id },
            status = 0,
          }))

          local res = assert(client:send({
            method = "PATCH",
            path = "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
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
            path = "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
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
            custom_id = "doggo2",
          }))

          local application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id },
            status = 0,
          }))

          local res = assert(client:send({
            method = "PATCH",
            path = "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
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
            suspended = false,
            status = 4,
          }))

          local creds = {}
          for row, err in db.daos["acls"]:each_for_consumer({ id = application.consumer.id }) do
            if row then table.insert(creds, row) end
          end

          assert.equal(#creds, 0)

          local res = assert(client:send({
            method = "PATCH",
            path = "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
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
            path = "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
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
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service.id },
          }))

          application = assert(db.applications:insert({
            developer = { id = developer.id },
            name = "bonesRcool",
            custom_id = "doggo",
          }))

          application_instance = assert(db.application_instances:insert({
            service = { id = service.id },
            application = { id  = application.id },
            status = statuses.APPROVED,
          }))
        end)

        after_each(function()
          db:truncate('basicauth_credentials')
          db:truncate("services")
          db:truncate("consumers")
          db:truncate("developers")
          db:truncate("applications")
        end)

        it("can delete existing application_instance", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)

          local application_instance, err, err_t = db.application_instances:select({ id = application_instance.id })

          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.is_nil(application_instance)
        end)

        it("deletes ACL group when application_instance is removed", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/applications/" .. application.id .. "/application_instances/" .. application_instance.id,
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
            path = "/applications/" .. application.id .. "/application_instances/" .. utils.uuid(),
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)
        end)
      end)
    end)
  end)
end
