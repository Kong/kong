local constants = require("kong.constants")

describe("Constants", function()
  it("Tests accessing database error codes", function()
    assert.has_no_error(function() local a = constants.DATABASE_ERROR_TYPES.DATABASE end)
    assert.has_error(function() local a = constants.DATABASE_ERROR_TYPES.ThIs_TyPe_DoEs_NoT_ExIsT end)
  end)

end)
