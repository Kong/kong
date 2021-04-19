-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

_G.kong = {}
local emails     = require "kong.portal.emails"
local singletons  = require "kong.singletons"

describe("ee portal emails", function()
  local portal_emails
  local snapshot
  local _files = {}

  before_each(function()
    snapshot = assert:snapshot()
    singletons.configuration = {
      portal_token_exp = 3600,
      smtp_mock = true,
      portal_invite_email = true,
      portal_access_request_email = true,
      portal_approved_email = true,
      portal_reset_email = true,
      portal_reset_success_email = true,
      admin_gui_url = "http://localhost:8080",
      smtp_admin_emails = {"admin@example.com"},
    }
    singletons.db = {
      files = {
        select_by_path = function(self, path)
          return _files[path]
        end,
      }
    }
    ngx.ctx.workspace = "mock_uuid"
    kong.db = {
      workspaces = {
        select = function()
          return { id = ngx.ctx.workspace }
        end
      }
    }
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("should work without emails files", function()
    describe("invite", function()
      it("should return err if portal_invite_email is disabled", function()
        singletons.configuration.portal_invite_email = false
        portal_emails = emails.new()

        local expected = {
          code = 501,
          message = "portal_invite_email is disabled",
        }

        local res, err = portal_emails:invite({"gruce@konghq.com"})
        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("should call client:send for each email passed", function()
        portal_emails = emails.new()
        spy.on(portal_emails.client, "send")

        local expected = {
          smtp_mock = true,
          error = {
            count = 0,
            emails = {},
          },
          sent = {
            count = 2,
            emails = {
              ["gruce2@konghq.com"] = true,
              ["gruce@konghq.com"] = true,
            }
          }
        }

        local res, err = portal_emails:invite({"gruce@konghq.com", "gruce2@konghq.com"})
        assert.same(expected, res)
        assert.is_nil(err)
        assert.spy(portal_emails.client.send).was_called(2)
      end)
    end)


    describe("password reset", function()
      it("should return err if portal_reset_email is disabled", function()
        singletons.configuration.portal_reset_email = false
        portal_emails = emails.new()

        local expected = {
          code = 501,
          message = "portal_reset_email is disabled",
        }

        local res, err = portal_emails:password_reset("gruce@konghq.com", "token")
        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("should call client:send", function()
        portal_emails = emails.new()
        spy.on(portal_emails.client, "send")

        local expected = {
          smtp_mock = true,
          error = {
            count = 0,
            emails = {},
          },
          sent = {
            count = 1,
            emails = {
              ["gruce@konghq.com"] = true,
            }
          }
        }

        local res, err = portal_emails:password_reset("gruce@konghq.com", "token")
        assert.same(expected, res)
        assert.is_nil(err)
        assert.spy(portal_emails.client.send).was_called(1)
      end)
    end)

    describe("access_request", function()
      it("should return nothing if portal_access_request_email is disbled", function()
        singletons.configuration.portal_access_request_email = false
        portal_emails = emails.new()

        local res, err = portal_emails:access_request("gruce@konghq.com", "Gruce")
        assert.is_nil(res)
        assert.is_nil(err)
      end)

      it("should call client:send", function()
        portal_emails = emails.new()
        spy.on(portal_emails.client, "send")

        local expected = {
          smtp_mock = true,
          error = {
            count = 0,
            emails = {},
          },
          sent = {
            count = 1,
            emails = {
              ["admin@example.com"] = true,
            }
          }
        }

        local res, err = portal_emails:access_request("gruce@konghq.com", "Gruce")
        assert.same(expected, res)
        assert.is_nil(err)
        assert.spy(portal_emails.client.send).was_called(1)
      end)
    end)

    describe("approved", function()
      it("should return nothing if portal_approved_email is disabled", function()
        singletons.configuration.portal_approved_email = false
        portal_emails = emails.new()

        local res, err = portal_emails:approved("gruce@konghq.com")
        assert.is_nil(res)
        assert.is_nil(err)
      end)

      it("should call client:send", function()
        portal_emails = emails.new()
        portal_emails.enabled = true
        spy.on(portal_emails.client, "send")

        local expected = {
          smtp_mock = true,
          error = {
            count = 0,
            emails = {},
          },
          sent = {
            count = 1,
            emails = {
              ["gruce@konghq.com"] = true,
            }
          }
        }

        local res, err = portal_emails:approved("gruce@konghq.com")
        assert.same(expected, res)
        assert.is_nil(err)
        assert.spy(portal_emails.client.send).was_called(1)
      end)
    end)

    describe("password_reset", function()
      it("should return err if portal_reset_email is disabled", function()
        singletons.configuration.portal_reset_email = false
        portal_emails = emails.new()

        local expected = {
          code = 501,
          message = "portal_reset_email is disabled",
        }

        local res, err = portal_emails:password_reset("gruce@konghq.com", 'token')
        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("should call client:send", function()
        portal_emails = emails.new()
        portal_emails.enabled = true
        spy.on(portal_emails.client, "send")

        local expected = {
          smtp_mock = true,
          error = {
            count = 0,
            emails = {},
          },
          sent = {
            count = 1,
            emails = {
              ["gruce@konghq.com"] = true,
            }
          }
        }

        local res, err = portal_emails:password_reset("gruce@konghq.com" ,'token')
        assert.same(expected, res)
        assert.is_nil(err)
        assert.spy(portal_emails.client.send).was_called(1)
      end)
    end)

    describe("password_reset_success", function()
      it("should return err if portal_reset_success_email is disabled", function()
        singletons.configuration.portal_reset_success_email = false
        portal_emails = emails.new()

        local expected = {
          code = 501,
          message = "portal_reset_success_email is disabled",
        }

        local res, err = portal_emails:password_reset_success("gruce@konghq.com")
        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("should call client:send", function()
        portal_emails = emails.new()
        portal_emails.enabled = true
        spy.on(portal_emails.client, "send")

        local expected = {
          smtp_mock = true,
          error = {
            count = 0,
            emails = {},
          },
          sent = {
            count = 1,
            emails = {
              ["gruce@konghq.com"] = true,
            }
          }
        }

        local res, err = portal_emails:password_reset_success("gruce@konghq.com")
        assert.same(expected, res)
        assert.is_nil(err)
        assert.spy(portal_emails.client.send).was_called(1)
      end)
    end)
  end)

  describe("should work with email template files", function()
    it("should replace tokens in view", function()
      local tokens = {
        ["portal.url"] = "www.greatestPortal.com",
        ["email.developer_email"] = "SomeDev@example.com",
        ["email.token"] = "great token",
        ["email.token_exp"] = "1234",
      }
      local view = "Vist {{portal.url }}/{{email.token_exp}}, {{   email.developer_email}}"
      local expected = "Vist www.greatestPortal.com/1234, SomeDev@example.com"
      assert.same(expected, emails:replace_tokens(view, tokens))
    end)
  end)
end)
