local uuid = require "uuid"
local Faker = require "kong.tools.faker"
local DaoError = require "kong.dao.error"

describe("Faker #tools", function()

  local ENTITIES_TYPES = { "api", "consumer", "basicauth_credential", "keyauth_credential", "plugin_configuration" }

  local factory_mock = {}
  local insert_spy
  local faker

  before_each(function()
    insert_spy = spy.new(function(self, t)
                          t.id = uuid()
                          return t
                        end)

    for _, v in ipairs(ENTITIES_TYPES) do
      factory_mock[v=="plugin_configuration" and "plugins_configurations" or v.."s"] = {
        insert = insert_spy
      }
    end

    faker = Faker(factory_mock)
  end)

  after_each(function()
    insert_spy:revert()
  end)

  it("should have an 'inserted_entities' property for relations", function()
    assert.truthy(faker.inserted_entities)
    assert.are.same("table", type(faker.inserted_entities))
  end)

  describe("#fake_entity()", function()

    it("should return a fake entity for each type", function()
      for _, v in ipairs(ENTITIES_TYPES) do
        local t = faker:fake_entity(v)
        assert.truthy(t)
        assert.are.same("table", type(t))
      end
    end)

    it("should throw an error if the type doesn't exist", function()
      local func_err = function() local t = faker:fake_entity("foo") end
      assert.has_error(func_err, "Entity of type foo cannot be generated.")
    end)

  end)

  describe("#seed()", function()
    local spy_insert_from_table

    before_each(function()
      spy_insert_from_table = spy.on(faker, "insert_from_table")
    end)

    after_each(function()
      spy_insert_from_table:revert()
    end)

    it("should call insert_from_table()", function()
      faker:seed()
      assert.spy(faker.insert_from_table).was.called(1)
    end)

    it("should populate the inserted_entities table for relations", function()
      faker:seed()

      for _, v in ipairs(ENTITIES_TYPES) do
        assert.truthy(faker.inserted_entities[v])
      end
    end)

    it("should be possible to add some random entities complementing the default hard-coded ones", function()
      faker:seed(2000)
      assert.spy(faker.insert_from_table).was.called(2)
      assert.spy(insert_spy).was.called(8025) -- 3*2000 + base entities
    end)

    it("should create relations between entities_to_insert and inserted entities", function()
      faker:seed()

      for type, entities in pairs(Faker.FIXTURES) do
        for i, entity in ipairs(entities) do
          -- assert object has been inserted
          local inserted_entity = faker.inserted_entities[type][i]
          assert.truthy(inserted_entity)

          -- discover if this entity had any hard-coded relation
          for _, v in ipairs(ENTITIES_TYPES) do
            local has_relation = entity["__"..v] ~= nil
            if has_relation then
              -- check the relation was respected
              assert.truthy(inserted_entity[v.."_id"])
            end
          end
        end
      end
    end)

    it("should throw a descriptive error if cannot insert an entity", function()
      local printable_mt = require "kong.tools.printable"
      local entity_to_str = setmetatable(Faker.FIXTURES.api[1], printable_mt)

      factory_mock.apis.insert = function(self, t)
                                   return nil, DaoError("cannot insert api error test", "schema")
                                 end
      assert.has_error(function()
        faker:seed()
      end, "Faker failed to insert api entity: "..entity_to_str.."\ncannot insert api error test")
    end)

  end)
end)
