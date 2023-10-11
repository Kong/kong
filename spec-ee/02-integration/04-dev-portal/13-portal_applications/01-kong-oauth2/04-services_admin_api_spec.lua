-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local utils = require "kong.tools.utils"


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
        license_path = "spec-ee/fixtures/mock_license.json",
        portal = true,
        portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
        portal_auth = "basic-auth",
        portal_app_auth = "kong-oauth2",
        portal_session_conf = "{ \"secret\": \"super-secret\" }",
      }))

      -- these need to be set so that setup and before hooks have the correct conf
      kong.configuration = { portal_auth = "basic-auth",  portal_app_auth = "kong-oauth2" }
      kong.configuration = { portal_auth = "basic-auth",  portal_app_auth = "kong-oauth2" }
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

    describe("/services/:services/applications", function()
      describe("GET", function()
        local developer,
              application_one,
              application_two,
              service_one,
              service_two

        lazy_setup(function()
          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

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
              display_name = "dope plugin",
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
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service_two.id },
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

          assert(db.application_instances:insert({
            service = { id = service_one.id },
            application = { id  = application_one.id }
          }))

          assert(db.application_instances:insert({
            service = { id = service_two.id },
            application = { id  = application_two.id }
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

        it("can return applications attached to the service", function()
          local res = assert(client:send({
            method = "GET",
            path = "/services/" .. service_one.id .. "/applications",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(json.data[1].id, application_one.id)

          res = assert(client:send({
            method = "GET",
            path = "/services/" .. service_two.id .. "/applications",
            headers = {["Content-Type"] = "application/json"}
          }))
          body = assert.res_status(200, res)
          json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(json.data[1].id, application_two.id)
        end)

        it("returns empty results when service has no applications", function()
          local service_three = assert(db.services:insert({
            name = "service_three",
            url = "http://google.com"
          }))

          local res = assert(client:send({
            method = "GET",
            path = "/services/" .. service_three.id .. "/applications",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 0)
        end)
      end)
    end)

    describe("/services/:services/application_instances", function()
      describe("GET", function()
        local developer,
              service_one,
              service_two,
              application_one,
              application_two

        lazy_setup(function()
          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

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
              display_name = "dope plugin",
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
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service_two.id },
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

          assert(db.application_instances:insert({
            service = { id = service_one.id },
            application = { id  = application_one.id }
          }))

          assert(db.application_instances:insert({
            service = { id = service_two.id },
            application = { id  = application_two.id }
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

        it("can return application_instances attached to the service", function()
          local res = assert(client:send({
            method = "GET",
            path = "/services/" .. service_one.id .. "/application_instances",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(json.data[1].application.id, application_one.id)
          assert(json.data[1].application.developer.email)
          assert(json.data[1].application.redirect_uri)

          res = assert(client:send({
            method = "GET",
            path = "/services/" .. service_two.id .. "/application_instances",
            headers = {["Content-Type"] = "application/json"}
          }))
          body = assert.res_status(200, res)
          json = cjson.decode(body)

          assert.equal(#json.data, 1)
          assert.equal(json.data[1].application.id, application_two.id)
          assert(json.data[1].application.developer.email)
          assert(json.data[1].application.redirect_uri)
        end)

        it("returns empty results when service has no application services", function()
          local service_three = assert(db.services:insert({
            name = "service_three",
            url = "http://google.com"
          }))

          local res = assert(client:send({
            method = "GET",
            path = "/services/" .. service_three.id .. "/applications",
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(#json.data, 0)
        end)
      end)
    end)

    describe("/services/:services/application_instances/:application_instances", function()
      describe("GET", function()
        local developer,
              service_one,
              service_two,
              application_one,
              application_two,
              app_instance_one,
              app_instance_two

        lazy_setup(function()
          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

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
              display_name = "dope plugin",
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
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service_two.id },
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

          app_instance_one = assert(db.application_instances:insert({
            service = { id = service_one.id },
            application = { id  = application_one.id }
          }))

          app_instance_two = assert(db.application_instances:insert({
            service = { id = service_two.id },
            application = { id  = application_two.id }
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

        it("can retrieve application instance", function()
          local res = assert(client:send({
            method = "GET",
            path = "/services/" .. service_one.id .. "/application_instances/" .. app_instance_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(json.application.id, application_one.id)
          assert(json.application.developer.email)
          assert(json.application.redirect_uri)

          res = assert(client:send({
            method = "GET",
            path = "/services/" .. service_two.id .. "/application_instances/" .. app_instance_two.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          body = assert.res_status(200, res)
          json = cjson.decode(body)

          assert.equal(json.application.id, application_two.id)
          assert(json.application.developer.email)
          assert(json.application.redirect_uri)
        end)

        it("cannot retrieve instance from wrong service", function()
          local res = assert(client:send({
            method = "GET",
            path = "/services/" .. service_two.id .. "/application_instances/" .. app_instance_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        local developer,
              service_one,
              service_two,
              application_one,
              application_two,
              app_instance_one

        before_each(function()
          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

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
              display_name = "dope plugin",
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
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service_two.id },
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

          app_instance_one = assert(db.application_instances:insert({
            service = { id = service_one.id },
            application = { id  = application_one.id }
          }))

          assert(db.application_instances:insert({
            service = { id = service_two.id },
            application = { id  = application_two.id }
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

        it("can patch an application_instance status", function()
          local res = assert(client:send({
            method = "PATCH",
            path = "/services/" .. service_one.id .. "/application_instances/" .. app_instance_one.id,
            body = {
              status = 3
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(json.status, 3)
        end)

        it("cannot patch application_instance with wrong service", function()
          local res = assert(client:send({
            method = "PATCH",
            path = "/services/" .. service_two.id .. "/application_instances/" .. app_instance_one.id,
            body = {
              application = { id = service_two.id },
              service = { id = service_two.id },
              composite_id = utils.uuid(),
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(404, res)
        end)

        it("cannot patch application_instance with invalid params", function()
          local res = assert(client:send({
            method = "PATCH",
            path = "/services/" .. service_one.id .. "/application_instances/" .. app_instance_one.id,
            body = {
              application = { id = service_two.id },
              service = { id = service_two.id },
              composite_id = utils.uuid(),
            },
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(json.application.id, application_one.id)
          assert.equal(json.service.id, service_one.id)
          assert.equal(json.composite_id, app_instance_one.composite_id)
        end)
      end)

      describe("DELETE", function()
        local developer,
              service_one,
              service_two,
              application_one,
              application_two,
              app_instance_one

        before_each(function()
          developer = assert(db.developers:insert({
            email = "dog@bork.com",
            password = "woof",
            meta = '{ "full_name": "todd" }',
          }))

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
              display_name = "dope plugin",
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
              display_name = "dope plugin",
            },
            name = "application-registration",
            service = { id = service_two.id },
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

          app_instance_one = assert(db.application_instances:insert({
            service = { id = service_one.id },
            application = { id  = application_one.id }
          }))

          assert(db.application_instances:insert({
            service = { id = service_two.id },
            application = { id  = application_two.id }
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

        it("can delete an application_instance", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/services/" .. service_one.id .. "/application_instances/" .. app_instance_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)
          assert.is_nil(kong.db.application_instances:select({ id = app_instance_one.id }))
        end)

        it("cannot delete an application_instance with wrong service", function()
          local res = assert(client:send({
            method = "DELETE",
            path = "/services/" .. service_two.id .. "/application_instances/" .. app_instance_one.id,
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)
          assert(kong.db.application_instances:select({ id = app_instance_one.id }))
        end)
      end)
    end)
  end)
end
