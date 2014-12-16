local Api = require "apenode.models.api"
local inspect = require "inspect"
describe("API Model", function()

  it("should work", function()
    local entity = Api({
      name = "HttpBin",
      public_dns = "public asd",
      target_url = "target asdads",
      wot = 123
    })



    print(inspect(entity))


    print(entity.public_dns)

    local data, err = entity:save()
    print(inspect(err))
  end)

end)
