local Schema = require("kong.db.schema")

describe("Plugin: file-log (schema)", function()

  local tests = {
    {
      name = "path is required",
      input = {
        reopen = true
      },
      output = nil,
      error = {
        config = {
          path = "required field missing"
        }
      }
    },
    ----------------------------------------
    {
      name = "rejects invalid filename",
      input = {
        path = "/ovo*",
        reopen = true
      },
      output = nil,
      error = {
        config = {
          path = "not a valid filename"
        }
      }
    },
    ----------------------------------------
    {
      name = "accepts valid filename",
      input = {
        path = "/tmp/log.txt",
        reopen = true
      },
      output = true,
      error = nil,
    },
  }

  local file_log_schema

  lazy_setup(function()
    file_log_schema = Schema.new(require("kong.plugins.file-log.schema"))
  end)

  for _, t in ipairs(tests) do
    it(t.name, function()
      local output, err = file_log_schema:validate({
        protocols = { "http" },
        config = t.input
      })
      assert.same(t.output, output)
      assert.same(t.error, err)
    end)
  end
end)
