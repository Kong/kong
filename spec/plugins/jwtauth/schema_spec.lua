local validate_entity = require("kong.dao.schemas_validation").validate_entity
local jwtschema = require "kong.plugins.jwtauth.schema"

require "kong.tools.ngx_stub"

describe("JwtAuth schema", function()

    it("should confirm a valid jwtschema is valid", function()
      local values = { id_names = {'hi', 'hi'}, hide_credentials = false }
      local valid, err = validate_entity(values, jwtschema)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should confirm an invalid jwtschema is invalid", function()
      local values = { id_names = {'hi', 'hi'}, blah = false, hide_credentials = false }
      local valid, err = validate_entity(values, jwtschema)
      assert.truthy(err)
      assert.falsy(valid)
    end)

    it("should confirm jwtschema returns default values", function()
      local default_id = jwtschema.fields.id_names.default({})
      local default_hide_credentials = jwtschema.fields.hide_credentials.default
      assert.equal(false, default_hide_credentials)
      assert.equal("id", default_id[1])
    end)

end)