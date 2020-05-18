local smtp_client = require "kong.enterprise_edition.smtp_client"

describe("ee smtp client", function()
  describe("send", function ()
    local client, options

    before_each(function()
      client = smtp_client.new({}, true)
      spy.on(client.mailer, "send")

      options = {
        some_option = true,
        another_option = "awesome"
      }
    end)

    it("should handle a valid email", function()
      local expected_res = {
        smtp_mock = true,
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
        smtp_mock = true,
        code = 400,
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
      assert.same(expected_res, res)
    end)

    it("should skip duplicate and invalid emails", function()
      local expected_res = {
        smtp_mock = true,
        code = 400,
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

      assert.same(expected_res, res)
    end)
  end)

  describe("handle_res", function()
    it("should return res if at least one email was sent", function()
      local email_res = {
        sent = {
          count = 1,
        },
        error = {
          count = 5,
        }
      }

      local res, err = smtp_client.handle_res(email_res)
      assert.same(email_res, res)
      assert.is_nil(err)
    end)

    it("should remove any error code if at least one email was sent", function()
      local email_res = {
        code = 400,
        sent = {
          count = 1,
        },
        error = {
          count = 5,
        }
      }

      local res, err = smtp_client.handle_res(email_res)
      assert.same(email_res, res)
      assert.is_nil(err)
    end)

    it("should return nil, error with code if no emails are sent and no code present", function()
      local email_res = {
        sent = {
          count = 0,
        },
        error = {
          count = 5,
        }
      }

      local expected_err = {
        message = email_res,
        code = 500
      }

      local res, err = smtp_client.handle_res(email_res)
      assert.is_nil(res)
      assert.same(expected_err, err)
    end)

    it("should return the error code if preset", function()
      local email_res = {
        code = 400,
        sent = {
          count = 0,
        },
        error = {
          count = 5,
        }
      }

      local expected_err = {
        message = email_res,
        code = 400
      }

      local res, err = smtp_client.handle_res(email_res)
      assert.is_nil(res)
      assert.same(expected_err, err)
    end)
  end)
end)
