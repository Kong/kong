local emails     = require "kong.portal.emails"

describe("ee portal emails", function()
  local conf
  local portal_emails
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
    conf = {
      smtp_mock = true,
      portal_invite_email = true,
      portal_access_request_email = true,
      portal_approved_email = true,
      portal_reset_email = true,
      portal_reset_success_email = true,
      smtp_admin_emails = {"admin@example.com"},
    }
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("invite", function()
    it("should return err if portal_invite_email is disabled", function()
      conf.portal_invite_email = false
      portal_emails = emails.new(conf)

      local expected = {
        code = 501,
        message = "portal_invite_email is disabled",
      }

      local res, err = portal_emails:invite({"gruce@konghq.com"})
      assert.is_nil(res)
      assert.same(expected, err)
    end)

    it("should call client:send for each email passed", function()
      portal_emails = emails.new(conf)
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
      conf.portal_reset_email = false
      portal_emails = emails.new(conf)

      local expected = {
        code = 501,
        message = "portal_reset_email is disabled",
      }

      local res, err = portal_emails:password_reset("gruce@konghq.com", "token")
      assert.is_nil(res)
      assert.same(expected, err)
    end)

    it("should call client:send", function()
      portal_emails = emails.new(conf)
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
      conf.portal_access_request_email = false
      portal_emails = emails.new(conf)

      local res, err = portal_emails:access_request("gruce@konghq.com", "Gruce")
      assert.is_nil(res)
      assert.is_nil(err)
    end)

    it("should call client:send", function()
      portal_emails = emails.new(conf)
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
      conf.portal_approved_email = false
      portal_emails = emails.new(conf)

      local res, err = portal_emails:approved("gruce@konghq.com")
      assert.is_nil(res)
      assert.is_nil(err)
    end)

    it("should call client:send", function()
      portal_emails = emails.new(conf)
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
      conf.portal_reset_email = false
      portal_emails = emails.new(conf)

      local expected = {
        code = 501,
        message = "portal_reset_email is disabled",
      }

      local res, err = portal_emails:password_reset("gruce@konghq.com", 'token')
      assert.is_nil(res)
      assert.same(expected, err)
    end)

    it("should call client:send", function()
      portal_emails = emails.new(conf)
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
      conf.portal_reset_success_email = false
      portal_emails = emails.new(conf)

      local expected = {
        code = 501,
        message = "portal_reset_success_email is disabled",
      }

      local res, err = portal_emails:password_reset_success("gruce@konghq.com")
      assert.is_nil(res)
      assert.same(expected, err)
    end)

    it("should call client:send", function()
      portal_emails = emails.new(conf)
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
