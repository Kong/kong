local dao_factory = require "apenode.dao.sqlite"

local daos = {
  ApisDao = dao_factory.apis,
  AccountsDao = dao_factory.accounts,
  ApplicationsDao = dao_factory.applications
}

math.randomseed(os.time())

local function fake_entity(type, invalid)
  local r = math.random(1, 10000000)

  if type == "ApisDao" then
    local name
    if invalid then name = "httpbin1" else name = "random"..r end
    return {
      name = name,
      public_dns = "random"..r..".com",
      target_url = "http://random"..r..".com",
      authentication_type = "query",
    }
  elseif type == "AccountsDao" then
    local provider_id
    if invalid then provider_id = "provider1" else provider_id = "random_provider_id_"..r end
    return {
      provider_id = provider_id
    }
  elseif type == "ApplicationsDao" then
    return {
      account_id = 1,
      public_key = "random"..r,
      secret_key = "random"..r,
    }
  end
end

describe("BaseDao", function()

  setup(function()
    dao_factory.populate()
  end)

  teardown(function()
    dao_factory.drop()
  end)

  for dao_name, dao in pairs(daos) do
    describe(dao_name, function()

      describe("#get_all()", function()
        it("should return the 1st page of 30 entities by default", function()
          local result, err = dao:get_all()
          assert.are.equal(30, table.getn(result))
          assert.are.equal(1, result[1].id)
        end)
        it("should be able to specify a page size", function()
          local result = dao:get_all(1, 5)
          assert.are.equal(5, table.getn(result))
          assert.are.equal(1, result[1].id)
          assert.are.equal(4, result[4].id)
        end)
        it("should limit the page size to 100", function()
          local result = dao:get_all(8, 1000)
          assert.are.equal(100, table.getn(result))
        end)
        it("should be able to query any page from a paginated entity", function()
          local result = dao:get_all(3, 6)
          assert.are.equal(6, table.getn(result))
          assert.are.equal(13, result[1].id)
          assert.are.equal(16, result[4].id)
        end)
        it("should be able to query the last page from a paginated entity", function()
          local result = dao:get_all(8, 5)
          assert.are.equal(5, table.getn(result))
          assert.are.equal(36, result[1].id)
          assert.are.equal(40, result[5].id)
        end)
        it("should return the total number of entity too", function()
          local result, count = dao:get_all()
          assert.are.equal(1000, count)
        end)
      end)

      describe("#get_by_id()", function()
        it("should get an entity by id", function()
          local result = dao:get_by_id(4)
          assert.truthy(result)
          assert.are.equal(4, result.id)
        end)
        it("should return nil if entity does not exist", function()
          local result = dao:get_by_id(9999)
          assert.falsy(result)
          assert.are.equal(nil, result)
        end)
      end)

      describe("#save()", function()
        it("should save an account and return the id", function()
          local random_entity = fake_entity(dao_name)
          local saved_id, err = dao:save(random_entity)
          assert.falsy(err)
          assert.truthy(saved_id)
          local result = dao:get_by_id(saved_id)
          assert.truthy(result)
          assert.are.same(saved_id, result.id)
        end)
        it("should return an error if failed", function()
          if dao_name ~= "ApplicationsDao" then
            local random_entity = fake_entity(dao_name, true)
            local saved_id, err = dao:save(random_entity)
            assert.truthy(err)
            assert.falsy(saved_id)
          end
        end)
        it("should default the created_at timestamp", function()
          local random_entity = fake_entity(dao_name)
          local saved_id = dao:save(random_entity)
          local result = dao:get_by_id(saved_id)
          assert.truthy(result.created_at)
        end)
      end)

      describe("#update()", function()
        it("should update an entity", function()
          local random_entity = fake_entity(dao_name)
          random_entity.id = 1
          local result, err = dao:update(random_entity)
          assert.falsy(err)
          assert.truthy(result)
          result, err = dao:get_by_id(1)
          assert.falsy(err)

          if dao_name == "ApisDao" then
            assert.are.equal(random_entity.name, result.name)
          elseif dao_name == "AccountsDao" then
            assert.are.equal(random_entity.provider_id, result.provider_id)
          elseif dao_name == "ApplicationsDao" then
            assert.are.equal(random_entity.public_key, result.public_key)
            assert.are.equal(random_entity.secret_key, result.secret_key)
          end

        end)
      end)

      describe("#delete()", function()
        it("should delete an entity", function()
          local result, err = dao:delete(1)
          assert.falsy(err)
          assert.truthy(result)
          result, err = dao:get_by_id(1)
          assert.falsy(err)
          assert.falsy(result)
        end)
      end)

    end)
  end

end)
