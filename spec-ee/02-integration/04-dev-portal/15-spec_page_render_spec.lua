-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe"
local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"

local function configure_portal(db, config)
  db.workspaces:upsert_by_name("default", {
    name = "default",
    config = config,
  })
end

local function get_portal_documentation(portal_gui_client, doc_name)
  local res = select(1, portal_gui_client:send({
    method = "GET",
    path = "/default/documentation/" .. doc_name,
  }))
  return assert.res_status(200, res)
end

local function decode_html_entities(str)
  local entities = {
    ["&amp;"] = "&",
    ["&lt;"] = "<",
    ["&gt;"] = ">",
    ["&quot;"] = "\"",
    ["&#47;"] = "/",
    ["&apos;"] = "'",
  }
  for entity, char in pairs(entities) do
    str = str:gsub(entity, char)
  end
  return str
end

for _, strategy in helpers.each_strategy() do
  describe("Spec page rendering [#" .. strategy .. "]", function()

    describe("App registration", function()

      local db, admin_client, portal_api_client, portal_gui_client

      local test_service, test_plugin

      lazy_setup(function()
        _, db = helpers.get_db_utils(strategy)

        assert(db:truncate())

        assert(helpers.start_kong({
          database            = strategy,
          portal              = true,
          portal_auth         = "basic-auth",
          portal_session_conf = cjson.encode({
            cookie_name   = "portal_session",
            cookie_secure = false,
            secret        = "super-secret",
            storage       = "kong",
          }),
          portal_cors_origins = "*",
          portal_auto_approve = true,
        }))

        configure_portal(db, {
          portal = true,
          portal_auth = "basic-auth",
        })

        assert(db.files:insert({
          path = "themes/default/layouts/system/spec-renderer.html",
          contents = "{{ json_encode(page.document_object) }}"
        }))

        test_service = assert(db.services:insert({
          name = "test_service",
          url = "http://google.com/test/service"
        }))

        assert(db.files:insert({
          path = "specs/cat.json",
          contents = [[
            {
              "layout": "system/spec-renderer.html",
              "swagger": "2.0",
              "info": {
                "description": "Meow~",
                "title": "cat.io",
                "version": "0.0.1"
              }
            }
          ]],
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        admin_client = helpers.admin_client()
        portal_api_client = ee_helpers.portal_api_client()
        portal_gui_client = ee_helpers.portal_gui_client()
      end)

      after_each(function()
        if admin_client then
          admin_client:close()
        end
        if portal_api_client then
          portal_api_client:close()
        end
        if portal_gui_client then
          portal_gui_client:close()
        end
      end)

      it("should render empty document object for the spec not linked with a service", function ()
        local body = get_portal_documentation(portal_gui_client, "cat")
        local document_object = cjson.decode(decode_html_entities(body))
        assert(next(document_object) == nil)
      end)

      it("should render correct document object for the spec linked with service but no plugin added", function ()
        local res = admin_client:send({
          method = "POST",
          path = "/services/" .. test_service.id .. "/document_objects",
          body = {
            path = "specs/cat.json",
            service = { id = test_service.id }
          },
          headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(200, res)

        local body = get_portal_documentation(portal_gui_client, "cat")
        local document_object = cjson.decode(decode_html_entities(body))
        assert.equals("specs/cat.json", document_object.path)
        assert.equals(test_service.id, document_object.service.id)
        assert.equals(nil, document_object.registration)
      end)

      it("should render correct document object for the spec linked with service and has plugin enabled", function ()
        test_plugin = assert(db.plugins:insert({
          config = {
            display_name = "access to cats!",
          },
          name = "application-registration",
          service = { id = test_service.id },
        }))

        local body = get_portal_documentation(portal_gui_client, "cat")
        local document_object = cjson.decode(decode_html_entities(body))
        assert.equals("specs/cat.json", document_object.path)
        assert.equals(test_service.id, document_object.service.id)
        assert.equals(true, document_object.registration)
      end)

      it("should render correct document object for the spec linked with service and has plugin disabled", function ()
        assert(db.plugins:update({ id = test_plugin.id }, {
          enabled = false,
        }))

        local body = get_portal_documentation(portal_gui_client, "cat")
        local document_object = cjson.decode(decode_html_entities(body))
        assert.equals("specs/cat.json", document_object.path)
        assert.equals(test_service.id, document_object.service.id)
        assert.equals(nil, document_object.registration)
      end)
    end)
  end)
end
