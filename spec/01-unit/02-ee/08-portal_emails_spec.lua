local emails     = require "kong.portal.emails"
local smtp_client = require "kong.enterprise_edition.smtp_client"

local function stub_client(send, check_conf)
  return {
    send = spy.new(function()
      return send.res, send.err
    end),
    check_conf = spy.new(function()
      return check_conf.res, check_conf.err
    end),
    }
end

describe("ee portal emails", function()
  local conf
  local portal_emails

  before_each(function()
    conf = {
      smtp = true,
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
    it("should return nil if smtp is disabled", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = false
      local ok, err = portal_emails:invite({"gruce@konghq.com"})
      assert.is_nil(ok)
      assert.is_nil(err)
    end)

    it("should return nil, err if check_conf returns an error", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = true
      portal_emails.client = stub_client({}, {
          res = nil,
          err = "error!!"
        }
      )

      local ok, err = portal_emails:invite({"gruce@konghq.com"})
      assert.is_nil(ok)
      assert.same("error!!", err)
    end)

    it("should call client:send for each email passed", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = true
      portal_emails.client = stub_client({res = true}, {res = true})
      spy.on(portal_emails.client, "send")

      local ok, err = portal_emails:invite({"gruce@konghq.com", "gruce2@konghq.com"})
      assert.is_true(ok)
      assert.is_nil(err)
      assert.spy(portal_emails.client.send).was_called(2)
    end)
  end)

  describe("access_request", function()
    it("should return nil if smtp is disabled", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = false
      local ok, err = portal_emails:access_request("gruce@konghq.com", "Gruce")
      assert.is_nil(ok)
      assert.is_nil(err)
    end)

    it("should return nil, err if check_conf returns an error", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = true
      portal_emails.client = stub_client(nil, {
          res = nil,
          err = "error!!"
        }
      )

      local ok, err = portal_emails:access_request("gruce@konghq.com", "Gruce")
      assert.is_nil(ok)
      assert.same("error!!", err)
    end)

    it("should call client:send", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = true
      portal_emails.client = stub_client({res = true}, {res = true})

      local ok, err = portal_emails:access_request("gruce@konghq.com", "Gruce")
      assert.is_true(ok)
      assert.is_nil(err)
      assert.spy(portal_emails.client.send).was_called(1)
    end)
  end)

  describe("approved", function()
    it("should return nil if smtp is disabled", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = false
      local ok, err = portal_emails:approved("gruce@konghq.com")
      assert.is_nil(ok)
      assert.is_nil(err)
    end)

    it("should return nil, err if check_conf returns an error", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = true
      portal_emails.client = stub_client(nil, {
          res = nil,
          err = "error!!"
        }
      )

      local ok, err = portal_emails:approved("gruce@konghq.com")
      assert.is_nil(ok)
      assert.same("error!!", err)
    end)

    it("should call client:send", function()
      portal_emails = emails.new(conf)
      portal_emails.enabled = true
      portal_emails.client = stub_client({res = true}, {res = true})

      local ok, err = portal_emails:approved("gruce@konghq.com")
      assert.is_true(ok)
      assert.is_nil(err)
      assert.spy(portal_emails.client.send).was_called(1)
    end)
  end)
end)
