-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Schema = require "kong.db.schema"
local workspaces = require "kong.db.schema.entities.workspaces"

local png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQAgMAAABinRfyAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAACVBMVEUAAAAAhP////8Zvt9xAAAAAXRSTlMAQObYZgAAAAFiS0dEAmYLfGQAAAAHdElNRQfkDBIRATfCo9woAAAAAW9yTlQBz6J3mgAAACFJREFUCNdjYIADERbWECDB4MDAAieAIshcFlYwARTFBQCWOAMurJBAVAAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyMC0xMi0xOFQxNzowMTo1NSswMDowMPycopoAAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjAtMTItMThUMTc6MDE6MzgrMDA6MDAqeXJhAAAAAElFTkSuQmCC"
local jpeg = "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/4QBiRXhpZgAATU0AKgAAAAgABQESAAMAAAABAAEAAAEaAAUAAAABAAAASgEbAAUAAAABAAAAUgEoAAMAAAABAAEAAAITAAMAAAABAAEAAAAAAAAAAAABAAAAAQAAAAEAAAAB/9sAQwADAgICAgIDAgICAwMDAwQGBAQEBAQIBgYFBgkICgoJCAkJCgwPDAoLDgsJCQ0RDQ4PEBAREAoMEhMSEBMPEBAQ/9sAQwEDAwMEAwQIBAQIEAsJCxAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ/8AAEQgAEAAQAwERAAIRAQMRAf/EABcAAAMBAAAAAAAAAAAAAAAAAAMEBgj/xAAjEAABBAMAAgEFAAAAAAAAAAADAQIEBQYREgAHIRMUFhcj/8QAFwEAAwEAAAAAAAAAAAAAAAAAAgMFBv/EACYRAAICAgEDBAIDAAAAAAAAAAECAxEEEiEABRMVIjNBFDEyQlH/2gAMAwEAAhEDEQA/AN1H9jZJRWeSYvY3tnPsQ55VQoEkePkSKCslmrnrFedglA1zRyTD6I9CO21yaVzE83idkxcuLHy4o1VDjSswMg2MkazDcKWDkFkVqVdRyOQG6xLd4ycWWfFkkZnGRGqnxnURuYjoWClAQrsts2x4PBI6q7gWS/tqlrY2eXMaqn1k6zLXDjwVD1FNBG0aPfHUqMekgqv/AKdbVOXMRNeRsZsT0aaV8dDIrogYmS6dZSTQcLa6DX21X8g3VbIXK9XiiXIYRsrsVAjr2GIVZQtR2O3uv/COnMl9X0+S0+R05bi5gfktnEtjyoEhgpEaRHZFaNwH8Lxr7MS7VFXauVFT40jB79PgzwThEbwoyAMCVZXMhOwsX8jD6FVYPNvzeyQ5sM8Jdl8rK5KkBgyhANTXHxqfs3dH9UewwORPzWJmyZxfxiQRPjhgCHCWKgCOA4wl6juKrSOjDVy/U6T54cxF14EPd1hwGwPx0IYgliZNtgGCtxIFtQ5AGtHjYHo5e1NLnLnedwVBAUaa0SpYcoWpios7WP6kdf/Z"
local gif = "data:image/gif;base64,R0lGODlhEAAQAPAAAAAAAACE/yH5BAEAAAAAIf8LSW1hZ2VNYWdpY2sNZ2FtbWE9MC40NTQ1NQAh/wtYTVAgRGF0YVhNUDw/eHBhY2tldCBiZWdpbj0n77u/JyBpZD0nVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkJz8+Cjx4OnhtcG1ldGEgeG1sbnM6eD0nYWRvYmU6bnM6bWV0YS8nIHg6eG1wdGs9J0ltYWdlOjpFeGlmVG9vbCAxMi4wNCc+CjxyZGY6UkRGIHhtbG5zOnJkZj0naHR0cDovL3d3dy53My5vcmcvMTk5OS8wMi8yMi1yZGYtc3ludGF4LW5zIyc+CgogPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9JycKICB4bWxuczp0aWZmPSdodHRwOi8vbnMuYWRvYmUuY29tL3RpZmYvMS4wLyc+CiAgPHRpZmY6T3JpZW50YXRpb24+MTwvdGlmZjpPcmllbnRhdGlvbj4KIDwvcmRmOkRlc2NyaXB0aW9uPgo8L3JkZjpSREY+CjwveDp4bXBtZXRhPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAo8P3hwYWNrZXQgZW5kPSd3Jz8+Af/+/fz7+vn49/b19PPy8fDv7u3s6+rp6Ofm5eTj4uHg397d3Nva2djX1tXU09LR0M/OzczLysnIx8bFxMPCwcC/vr28u7q5uLe2tbSzsrGwr66trKuqqainpqWko6KhoJ+enZybmpmYl5aVlJOSkZCPjo2Mi4qJiIeGhYSDgoGAf359fHt6eXh3dnV0c3JxcG9ubWxramloZ2ZlZGNiYWBfXl1cW1pZWFdWVVRTUlFQT05NTEtKSUhHRkVEQ0JBQD8+PTw7Ojk4NzY1NDMyMTAvLi0sKyopKCcmJSQjIiEgHx4dHBsaGRgXFhUUExIREA8ODQwLCgkIBwYFBAMCAQAALAAAAAAQABAAAAIjhI+pmxH3jJsyAisb1Mji20zfuHUcaKYXRlYVxcTyTNf2UQAAOw=="

describe("workspace config", function()
  local schema

  setup(function()
    schema = Schema.new(workspaces)
  end)

  describe("schema", function()
    local snapshot

    before_each(function()
      snapshot = assert:snapshot()
    end)

    after_each(function()
      snapshot:revert()
    end)

    it("should accept properly formatted emails", function()
      local values = {
        name = "test",
        config = {
          portal_emails_from = "dog@kong.com",
          portal_emails_reply_to = "cat@kong.com",
        }
      }

      assert.truthy(schema:validate(values))
    end)

    it("should reject when email field is improperly formatted", function()
      local values = {
        name = "test",
        config = {
          portal_emails_from = "dog",
          portal_emails_reply_to = "cat",
        },
      }

      local ok, err = schema:validate(values)
      assert.falsy(ok)
      assert.equal("invalid email address dog", err.config["portal_emails_from"])
      assert.equal("invalid email address cat", err.config["portal_emails_reply_to"])
    end)

    it("should accept properly formatted token expiration", function()
      local values = {
        name = "test",
        config = {
          portal_token_exp = 1000,
        },
      }

      assert.truthy(schema:validate(values))
    end)

    it("should reject improperly formatted token expiration", function()
      local values = {
        name = "test",
        config = {
          portal_token_exp = -1000,
        },
      }

      local ok, err = schema:validate(values)
      assert.falsy(ok)
      assert.equal("value must be greater than -1", err.config["portal_token_exp"])
    end)

    it("should accept valid auth types", function()
      local values

      values = {
        name = "test",
        config = {
          portal_auth = "basic-auth",
        },
      }
      assert.truthy(schema:validate(values))

      values = {
        name = "test",
        config = {
          portal_auth = "key-auth",
        }
      }
      assert.truthy(schema:validate(values))

      values = {
        name = "test",
        config = {
          portal_auth = "openid-connect",
        },
      }
      assert.truthy(schema:validate(values))

      values = {
       name = "test",
       config = {
         portal_auth = "",
       },
      }
      assert.truthy(schema:validate(values))

      values = {
        name = "test",
        config = {
          portal_auth = nil,
        },
      }
      assert.truthy(schema:validate(values))
    end)

    it("should reject improperly formatted auth type", function()
      local values = {
        name = "test",
        config = {
          portal_auth = 'something-invalid',
        },
      }
      assert.falsy(schema:validate(values))
    end)

    it("should correctly merge new/old configs", function()
      local old_values = {
        name = "test",
        config = {
          portal = true,
          portal_auth = 'basic-auth',
        },
      }

      local new_values = {
        name = "test",
        config = {
          portal_auth = 'key-auth',
        },
      }

      local expected_values = {
        name = "test",
        config = {
          portal = true,
          portal_auth = 'key-auth',
        },
      }

      local values = schema:merge_values(new_values, old_values)

      assert.equals(values.config.portal, expected_values.config.portal)
      assert.equals(values.config.portal_auth, expected_values.config.portal_auth)
    end)

    it("should accept valid regex for portal_cors_origins", function()
      local values = {
        name = "test",
        config = {
          portal_cors_origins = { "wee" },
        },
      }

      assert.truthy(schema:validate(values))
    end)

    it("should accept '*' for portal_cors_origins", function()
      local values = {
        name = "test",
        config = {
          portal_cors_origins = { "*" },
        },
      }

      assert.truthy(schema:validate(values))
    end)

    it("should reject invalid regex (other than star) for portal_cors_origins", function()
      local values = {
        name = "test",
        config = {
          portal_cors_origins = { "[" },
        },
      }

      assert.falsy(schema:validate(values))
    end)

    it("should reject non string values for portal_cors_origins", function()
      local values = {
        name = "test",
        config = {
          portal_cors_origins = { 9000 },
        },
      }

      assert.falsy(schema:validate(values))
    end)

    it("should accept valid meta.color", function()
      local values = {
        name = "test",
        meta = {
          color = "#255255",
        },
      }

      assert.truthy(schema:validate(values))

      local values = {
        name = "test",
        meta = {
          color = "#e0e040",
        },
      }

      assert.truthy(schema:validate(values))

      local values = {
        name = "test",
        meta = {
          color = "#FF1493",
        },
      }

      assert.truthy(schema:validate(values))

      local values = {
        name = "test",
        meta = {
          color = "#EEEEEE",
        },
      }

      assert.truthy(schema:validate(values))
    end)

    it("should reject invalid meta.color", function()
      local values = {
        name = "test",
        meta = {
          color = "255255",
        },
      }

      assert.falsy(schema:validate(values))

      local values = {
        name = "test",
        meta = {
          color = "2552556",
        },
      }

      assert.falsy(schema:validate(values))

      local values = {
        name = "test",
        meta = {
          color = "#<script",
        },
      }

      assert.falsy(schema:validate(values))
    end)

    it("should accept valid meta.thumbnail", function()
      local values = {
        name = "test",
        meta = {
          thumbnail = png,
        },
      }

      assert.truthy(schema:validate(values))

      local values = {
        name = "test",
        meta = {
          thumbnail = jpeg,
        },
      }

      assert.truthy(schema:validate(values))

      local values = {
        name = "test",
        meta = {
          thumbnail = gif,
        },
      }

      assert.truthy(schema:validate(values))
    end)

    it("should reject invalid meta.thumbnail", function()
      local values = {
        name = "test",
        meta = {
          thumbnail = 'notvalid',
        },
      }

      assert.falsy(schema:validate(values))

      local values = {
        name = "test",
        meta = {
          thumbnail = 'data:binary/notvalid;notvalid',
        },
      }

      assert.falsy(schema:validate(values))

      local values = {
        name = "test",
        meta = {
          thumbnail = '<script>foo()</script>',
        },
      }

      assert.falsy(schema:validate(values))
    end)
  end)
end)
