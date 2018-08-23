local emails     = require "kong.portal.emails"
local smtp_client = require "kong.enterprise_edition.smtp_client"

describe("ee portal emails", function()
  local conf
  local portal_emails
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
    conf = {
      smtp = true,
      smtp_mock = true,
      smtp_admin_emails = {"admin@example.com"},
      admin_gui_url  = "http://127.0.0.1:8080",
      portal_gui_url = "http://0.0.0.0:8003",
      portal_emails_from = "meeeee <me@example.com>",
      portal_emails_reply_to = "me@example.com",
      portal_invite_email = true,
      portal_access_request_email = true,
      portal_approved_email = true,
    }
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("new", function()
    it("should set enabled false if smtp is off", function()
      conf.smtp = false
      portal_emails = emails.new(conf)
      assert.is_false(portal_emails.enabled)
    end)

    it("should set enabled false if unable initialize smtp client", function()
      stub(smtp_client, "new").returns(nil, "error")
      portal_emails = emails.new(conf)
      assert.is_false(portal_emails.enabled)
    end)

    it("should call smtp.prep_conf", function()
      spy.on(smtp_client, "prep_conf")
      portal_emails = emails.new(conf)
      assert.spy(smtp_client.prep_conf).was_called()
    end)
  end)

  describe("invite", function()
    it("should return error msg if smtp is disabled", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = false

      local expected = {
        code = 501,
        message = "smtp is disabled",
      }

      local res, err = portal_emails:invite({"gruce@konghq.com"})
      assert.is_nil(res)
      assert.same(expected, err)
    end)

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
      stub(smtp_client, "check_conf").returns(
                           portal_emails.conf.portal_invite_email, nil)
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

  describe("access_request", function()
    it("should return error msg if smtp is disabled", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = false

      local expected = {
        code = 501,
        message = "smtp is disabled",
      }

      local res, err = portal_emails:access_request("gruce@konghq.com", "Gruce")
      assert.is_nil(res)
      assert.same(expected, err)
    end)

    it("should return err if portal_access_request_email is disbled", function()
      conf.portal_access_request_email = false
      portal_emails = emails.new(conf)

      local expected = {
        code = 501,
        message = "portal_access_request_email is disabled",
      }

      local res, err = portal_emails:access_request("gruce@konghq.com", "Gruce")
      assert.is_nil(res)
      assert.same(expected, err)
    end)

    it("should call client:send", function()
      portal_emails = emails.new(conf)
      stub(smtp_client, "check_conf").returns(
                           portal_emails.conf.portal_access_request_email, nil)
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
    it("should return nil if smtp is disabled", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = false

      local expected = {
        code = 501,
        message = "smtp is disabled",
      }

      local res, err = portal_emails:approved("gruce@konghq.com")
      assert.is_nil(res)
      assert.same(expected, err)
    end)

    it("should return err if portal_approved_email is disabled", function()
      conf.portal_approved_email = false
      portal_emails = emails.new(conf)

      local expected = {
        code = 501,
        message = "portal_approved_email is disabled",
      }

      local res, err = portal_emails:approved("gruce@konghq.com")
      assert.is_nil(res)
      assert.same(expected, err)
    end)

    it("should call client:send", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = true
      stub(smtp_client, "check_conf").returns(
                  portal_emails.conf.portal_approved_email, nil)
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
end)
