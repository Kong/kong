
require("spec.helpers")

local compat = require("kong.clustering.compat")

local function reset_fields()
  compat._set_removed_fields(require("kong.clustering.compat.removed_fields"))
end

describe("kong.clustering.compat", function()
  describe("calculating fields to remove", function()
    before_each(reset_fields)
    after_each(reset_fields)

    it("merges multiple versions together", function()
      compat._set_removed_fields({
        [200] = {
          my_plugin = {
            "a",
            "c",
          },
          my_other_plugin = {
            "my_field",
          },
        },
        [300] = {
          my_plugin = {
            "b",
          },
          my_other_plugin = {
            "my_extra_field",
          },
          my_third_plugin = {
            "my_new_field",
          },
        },
      })

      assert.same(
        {
          my_plugin = {
            "a",
            "b",
            "c",
          },
          my_other_plugin = {
            "my_extra_field",
            "my_field",
          },
          my_third_plugin = {
            "my_new_field",
          },
        },
        compat._get_removed_fields(100)
      )
    end)

    it("memoizes the result", function()
      compat._set_removed_fields({
        [200] = {
          my_plugin = {
            "a",
            "c",
          },
          my_other_plugin = {
            "my_field",
          },
        },
        [300] = {
          my_plugin = {
            "b",
          },
          my_other_plugin = {
            "my_extra_field",
          },
          my_third_plugin = {
            "my_new_field",
          },
        },
      })

      local fields = compat._get_removed_fields(100)
      -- sanity
      assert.same(
        {
          my_plugin = {
            "a",
            "b",
            "c",
          },
          my_other_plugin = {
            "my_extra_field",
            "my_field",
          },
          my_third_plugin = {
            "my_new_field",
          },
        },
        fields
      )

      local other = compat._get_removed_fields(100)
      assert.equals(fields, other)

      fields = compat._get_removed_fields(200)
      assert.same(
        {
          my_plugin = {
            "b",
          },
          my_other_plugin = {
            "my_extra_field",
          },
          my_third_plugin = {
            "my_new_field",
          },
        },
        fields
      )

      other = compat._get_removed_fields(200)
      assert.equals(fields, other)
    end)

  end)

  describe("update_compatible_payload()", function()
    local test_with

    lazy_setup(function()
      test_with = function(plugins, dp_version)
        local has_update, new_conf = compat.update_compatible_payload(
          { plugins = plugins }, dp_version, ""
        )

        if has_update then
          return new_conf.plugins
        end

        return plugins
      end

      compat._set_removed_fields({
        [2000000000] = {
          my_plugin = {
            "delete_me",
          }
        },
        [3000000000] = {
          my_plugin = {
            "delete_me_too",
          },
          other_plugin = {
            "goodbye",
            "my.nested.field",
          },
        },
      })
    end)

    lazy_teardown(reset_fields)

    local cases = {
      {
        name = "empty",
        version = "3.0.0",
        plugins = {},
        expect = {}
      },

      {
        name = "merged",
        version = "1.0.0",
        plugins = {
          {
            name = "my-plugin",
            config = {
              do_not_delete = true,
              delete_me = false,
              delete_me_too = ngx.null,
            },
          },
          {
            name = "other-plugin",
            config = {
              hello = { a = 1 },
            },
          },
        },
        expect = {
          {
            name = "my-plugin",
            config = {
              do_not_delete = true,
            },
          },
          {
            name = "other-plugin",
            config = {
              hello = { a = 1 },
            },
          },
        },
      },

      {
        name = "nested fields",
        version = "1.0.0",
        plugins = {
          {
            name = "other-plugin",
            config = {
              do_not_delete = 1,
              my = 123,
            },
          },

          {
            name = "other-plugin",
            config = {
              do_not_delete = 1,
              my = {
                nested = "not a table",
              },
            },
          },

          {
            name = "other-plugin",
            config = {
              do_not_delete = 1,
              my = {
                nested = {
                  field = "this one",
                  stay = "I'm still here",
                }
              },
            },
          },
        },
        expect = {
          {
            name = "other-plugin",
            config = {
              do_not_delete = 1,
              my = 123,
            },
          },

          {
            name = "other-plugin",
            config = {
              do_not_delete = 1,
              my = {
                nested = "not a table",
              },
            },
          },

          {
            name = "other-plugin",
            config = {
              do_not_delete = 1,
              my = {
                nested = {
                  -- deleted
                  -- field = "this one",
                  stay = "I'm still here",
                }
              },
            },
          },
        },
      },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local result = test_with(case.plugins, case.version)
        assert.same(case.expect, result)
      end)
    end
  end)
end)
