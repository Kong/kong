local Schema = require "kong.db.schema"

describe("schema", function()
  describe("process_auto_fields", function()
    it("sets 'read_before_write' to true when updating field type record", function()
      local Test = Schema.new({
        name = "test",
        fields = {
          { config = { type = "record", fields = { foo = { type = "string" } } } },
        }
      })

      for _, operation in pairs{ "insert", "update", "select", "delete" } do
        local assertion = assert.falsy

        if operation == "update" then
          assertion = assert.truthy
        end

        local _, _, process_auto_fields = Test:process_auto_fields({
          config = {
            foo = "dog"
          }
        }, operation)

        assertion(process_auto_fields)
      end
    end)

    it("sets 'read_before_write' to false when not updating field type record", function()
      local Test = Schema.new({
        name = "test",
        fields = {
          { config = { type = "record", fields = { foo = { type = "string" } } } },
          { name = { type = "string" } }
        }
      })

      for _, operation in pairs{ "insert", "update", "select", "delete" } do
        local assertion = assert.falsy

        local _, _, process_auto_fields = Test:process_auto_fields({
          name = "cat"
        }, operation)

        assertion(process_auto_fields)
      end
    end)
  end)

  describe("merge_values", function()
    it("should correctly merge records", function()
      local Test = Schema.new({
        name = "test", fields = {
          { config = {
              type = "record",
              fields = {
                foo = { type = "string" },
                bar = { type = "string" }
              }
            }
          },
          { name = { type = "string" }
        }}
      })

      local old_values = {
        name = "test",
        config = { foo = "dog", bar = "cat" },
      }

      local new_values = {
        name = "test",
        config = { foo = "pig" },
      }

      local expected_values = {
        name = "test",
        config = { foo = "pig", bar = "cat" }
      }

      local values = Test:merge_values(new_values, old_values)

      assert.equals(values.config.foo, expected_values.config.foo)
      assert.equals(values.config.bar, expected_values.config.bar)
    end)
  end)
end)
