-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local helpers = require "spec.helpers"
local sampler_mod = require "kong.enterprise_edition.debug_session.sampler"

describe("sampler", function()

  local sampler
  setup(function()
    helpers.get_db_utils("off")
  end)

  before_each(function()
    sampler = sampler_mod:new()
  end)

  after_each(function()
  end)

  lazy_teardown(function()
  end)

  describe(":collect_sampler_fields_map #foo", function ()
    it("returns a map of fields", function()
      local fields_map = sampler:collect_sampler_fields_map()
      assert.is_table(fields_map)
    end)
  end)

  describe(":update_fields", function ()
    it("updates the fields of the sampler", function()
      stub(sampler, "collect_sampler_fields_map", function()
        return {
          ["foo.bar"] = {
            getter = function() return "foo.bar" end,
            type = "String"
          }
        }
      end)
      sampler:update_fields()
      assert.is_table(sampler.fields["foo.bar"])
      assert.is.same(sampler.fields["foo.bar"].getter(), "foo.bar")
      assert.is.same(sampler.fields["foo.bar"].type, "String")
    end)
  end)

  describe(":init_worker", function()
    before_each(function()
      stub(sampler, "load_schema")
      stub(sampler, "update_fields")
      stub(sampler, "initialize_router")
    end)

    after_each(function()
      sampler.load_schema:revert()
    end)

    it("updates fields and loads schema", function()
      sampler:init_worker()
      assert.stub(sampler.update_fields).was_called(1)
      assert.stub(sampler.load_schema).was_called(1)
      assert.stub(sampler.initialize_router).was_called()
    end)
  end)

  describe(":load_schema", function()
    -- we trust the schema to be loaded correctly
    -- this should be tested from the schema/atc module already
    it("loads the schema", function()
      assert.is_nil(sampler.schema)
      sampler:load_schema()
      assert.is_table(sampler.schema)
    end)
  end)

  describe(":initialize_router", function ()
    it("sets the router", function()
      assert.is_nil(sampler.router)
      sampler:load_schema()
      sampler:initialize_router()
      assert.is_table(sampler.router)
    end)
  end)

  describe(":add_matcher", function()
    it("calls the matcher", function()
      sampler:load_schema()
      sampler:initialize_router()
      stub(sampler.router, "add_matcher")
      sampler:add_matcher()
      assert.stub(sampler.router.add_matcher).was_called(1)
    end)
  end)

  describe(":populate_context", function ()
    it("populates the context", function()
      sampler:load_schema()
      sampler.fields["foo.bar"] = {
        getter = function() return "bar_baz" end,
        type = "String"
      }
      stub(sampler.context, "add_value")
      sampler:populate_context()
      assert.stub(sampler.context.add_value).was_called_with(sampler.context, "foo.bar", "bar_baz")
    end)
  end)

  describe("sample_in", function()
    local old_ngx_ctx = ngx.ctx

    lazy_setup(function()
      ngx.ctx = {
        request_uri = "/foo/bar",
        scheme = "http",
        cached_request_headers = {}
      }
    end)

    lazy_teardown(function()
      ngx.ctx = old_ngx_ctx
    end)

    it("runs router when expression is found", function()
      sampler:load_schema()
      sampler:initialize_router()
      sampler:update_fields({
        ["foo.bar"] = {
          getter = function() return "foo.bar" end,
          type = "String"
        }
      })
      sampler.expr = "foo == bar"
      stub(sampler.router, "execute")
      stub(sampler, "populate_context")
      sampler:sample_in()
      assert.stub(sampler.populate_context).was_called(1)
      assert.stub(sampler.router.execute).was_called(1)
    end)

    it("exits early when no expression is found", function()
      sampler:load_schema()
      sampler:initialize_router()
      sampler:update_fields({
        ["foo.bar"] = {
          getter = function() return "foo.bar" end,
          type = "String"
        }
      })
      stub(sampler.router, "execute")
      stub(sampler, "populate_context")
      sampler:sample_in()
      assert.stub(sampler.populate_context).was_called(0)
      assert.stub(sampler.router.execute).was_called(0)
    end)
  end)
end)
