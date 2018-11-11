local emails = require "kong.enterprise_edition.admin.emails"

describe("ee admin emails", function()
  local conf
  local admin_emails
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
    conf = {
      admin_invitation_expiry = 3600,
      smtp_mock = true,
      admin_invite_email = true,
      admin_access_request_email = true,
      admin_approved_email = true,
      admin_reset_email = true,
      admin_reset_success_email = true,
      smtp_admin_emails = {"admin@test.com"},
    }
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("invite", function()
    it("should return err if admin_gui_auth is disabled", function()
      conf.admin_gui_auth = false
      admin_emails = emails.new(conf)

      local expected = {
        code = 501,
        message = "admin_gui_auth is disabled",
      }

      local res, err = admin_emails:invite({"gruce@konghq.com"})
      assert.is_nil(res)
      assert.same(expected, err)
    end)

    it("should call client:send for each email passed", function()
      conf.admin_gui_auth = true
      admin_emails = emails.new(conf)
      spy.on(admin_emails.client, "send")

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

      local res, err = admin_emails:invite({"gruce@konghq.com", "gruce2@konghq.com"})
      assert.same(expected, res)
      assert.is_nil(err)
      assert.spy(admin_emails.client.send).was_called(2)
    end)
  end)
end)
