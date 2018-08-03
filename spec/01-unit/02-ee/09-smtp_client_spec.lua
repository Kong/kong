local smtp_client = require "kong.enterprise_edition.smtp_client"

describe("ee smtp client", function()
  describe("prep_conf", function()
    local conf, strategy_conf

    before_each(function()
      conf = {
        passing_email = true,
        failing_email = true,
        this_email_is_disabled = false,
        needed_key = true,
        super_important_key = "something",
        cannot_do_without = 9000,
        missing_key = "",
        uh_oh = {},
        doh = nil,
        falsy = false,
      }

      strategy_conf = {
        passing_email = {
          name = "Something",
          required_conf_keys = {
            "needed_key",
            "super_important_key",
            "cannot_do_without",
          },
          subject = "Do you like... emails?",
          html = "<h1>Haha emails are great!</h1>",
        },
        failing_email = {
          name = "Something 2",
          required_conf_keys = {
            "missing_key",
            "uh_oh",
            "doh",
            "falsy",
          },
          subject = "Congrats",
          html = "<h1>You are approved</h1>",
        },
        this_email_is_disabled = {
          name = "Something 3",
          required_conf_keys = {
            "needed_key",
            "super_important_key",
            "cannot_do_without",
          },
          subject = "This is email is disabled",
          html = "<h1>Reeeeeeee</h1>",
        }
      }
    end)

    it("maps required key value pairs from conf to strategy_conf", function()
      local res = smtp_client.prep_conf(conf, strategy_conf)

      assert.same(conf.needed_key, res.passing_email.needed_key)
      assert.same(conf.super_important_key, res.passing_email.super_important_key)
      assert.same(conf.cannot_do_without, res.passing_email.cannot_do_without)
      assert.is_nil(res.passing_email.missing_conf)
    end)

    it("lists the missing conf values in missing_conf", function()
      local res = smtp_client.prep_conf(conf, strategy_conf)

      assert.is_nil(res.failing_email.missing_key)
      assert.is_nil(res.failing_email.uh_oh)
      assert.is_nil(res.failing_email.doh)
      assert.is_nil(res.failing_email.falsy)

      assert.same("missing_key, uh_oh, doh, falsy", res.failing_email.missing_conf)
    end)

    it("sets an email conf to nil if the email is disabled", function()
      local res = smtp_client.prep_conf(conf, strategy_conf)

      assert.is_nil(res.this_email_is_disabled)
    end)

  end)

  describe("check_conf", function()
    local client

    before_each(function()
      client = smtp_client.new()
    end)

    it("returns nil, err if email is missing a required config", function()
      local conf = {
        name = "my_email",
        enabled = true,
        missing_conf = "this_key, that_key"
      }

      local ok, err = client:check_conf(conf)
      assert.is_nil(ok)
      assert.same("missing conf for my_email: this_key, that_key", err)
    end)

    it("returns true if email is ok to send", function()
      local conf = {
        name = "my_email",
        enabled = true,
      }

      local ok, err = client:check_conf(conf)
      assert.is_true(ok)
      assert.is_nil(err)
    end)
  end)

  describe("send", function ()
    local client, options

    before_each(function()
      client = smtp_client.new()

      client.mailer = {
        send = spy.new(function()
          return true
        end)
      }

      options = {
        some_option = true,
        another_option = "awesome"
      }
    end)

    it("should handle a valid email", function()
      local expected_res = {
        sent = {
          emails = {
            ["dev@something.com"] = true,
          },
          count = 1,
        },
        error = {
          emails = {},
          count = 0,
        },
      }

      local res = client:send({"dev@something.com"}, options)
      assert.spy(client.mailer.send).was.called()
      assert.same(res, expected_res)
    end)

    it("should handle an invalid email", function()
      local expected_res = {
        sent = {
          emails = {},
          count = 0,
        },
        error = {
          emails = {
            ["foo@bar@tld.com"] = "Invalid email: local-part invalid '@' character",
            ["@notevenclose"] = "Invalid email: missing local-part",
            ["areyoueventrying@"] = "Invalid email: missing domain",
            ["bademail"] = "Invalid email: missing '@' symbol",
            ["nope@nope"] = "Invalid email: domain missing '.' character",
            ["@whut.com"] = "Invalid email: missing local-part",
          },
          count = 6,
        },
      }

      local to_send = {
        "foo@bar@tld.com",
        "@notevenclose",
        "areyoueventrying@",
        "bademail",
        "nope@nope",
        "@whut.com"
      }

      local res = client:send(to_send, options)
      assert.spy(client.mailer.send).was_not.called()
      assert.same(res, expected_res)
    end)

    it("should skip duplicate and invalid emails", function()
      local expected_res = {
        sent = {
          emails = {
            ["dev2@something.com"] = true,
            ["dev3@something.com"] = true,
          },
          count = 2,
        },
        error = {
          emails = {
            ["emailol"] = "Invalid email: missing '@' symbol",
            ["derp@"] = "Invalid email: missing domain",
          },
          count = 2,
        },
      }

      local res = client:send({"dev2@something.com", "dev2@something.com"} , options)
      assert.spy(client.mailer.send).was.called()

      client:send({"emailol"}, options, res)
      assert.spy(client.mailer.send).was_not.called(2)

      client:send({"dev3@something.com"}, options, res)
      assert.spy(client.mailer.send).was.called(2)

      client:send({"dev2@something.com"}, options, res)
      assert.spy(client.mailer.send).was_not.called(3)

      client:send({"dev3@something.com"}, options, res)
      assert.spy(client.mailer.send).was_not.called(3)

      client:send({"derp@"}, options, res)
      assert.spy(client.mailer.send).was_not.called(3)
      client:send({"derp@"}, options, res)
      assert.spy(client.mailer.send).was_not.called(3)

      client:send({"emailol"}, options, res)
      assert.spy(client.mailer.send).was_not.called(3)

      client:send({"dev2@something.com"}, options, res)
      assert.spy(client.mailer.send).was_not.called(3)

      assert.same(res, expected_res)
    end)
  end)
end)
