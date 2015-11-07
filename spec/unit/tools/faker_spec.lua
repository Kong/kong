local uuid = require "lua_uuid"
local Faker = require "kong.tools.faker"
local DaoError = require "kong.dao.error"

describe("Faker", function()

  local ENTITIES_TYPES = { "api", "consumer", "plugin" }

  local factory_mock = {}
  local insert_spy
  local faker

  before_each(function()
    insert_spy = spy.new(function(self, t)
                          t.id = uuid()
                          return t
                        end)

    for _, v in ipairs(ENTITIES_TYPES) do
      factory_mock[v=="plugin" and "plugins" or v.."s"] = {
        insert = insert_spy
      }
    end

    faker = Faker(factory_mock)
  end)

  after_each(function()
    insert_spy:revert()
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
      local func_err = function() faker:fake_entity("foo") end
      assert.has_error(func_err, "Entity of type foo cannot be generated.")
    end)

  end)

  describe("#insert_from_table()", function()
    it("should throw a descriptive error if cannot insert an entity", function()
      local api_t = { name = "tests faker 1", request_host = "foo.com", upstream_url = "http://mockbin.com" }

      local printable_mt = require "kong.tools.printable"
      local entity_to_str = setmetatable(api_t, printable_mt)

      factory_mock.apis.insert = function(self, t)
                                   return nil, DaoError("cannot insert api error test", "schema")
                                 end
      assert.has_error(function()
        faker:insert_from_table({ api = { api_t } })
      end, "Faker failed to insert api entity: "..entity_to_str.."\ncannot insert api error test")
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

    it("should insert some random entities for apis and consumers", function()
      local fixtures = faker:seed(1)
      assert.truthy(fixtures.api)
      assert.truthy(fixtures.consumer)
    end)

    it("should create relations between entities_to_insert and inserted entities", function()
      local fixtures = {
        api = {
          { name = "tests faker 1", request_host = "foo.com", upstream_url = "http://mockbin.com" },
          { name = "tests faker 2", request_host = "bar.com", upstream_url = "http://mockbin.com" }
        },
        plugin = {
          { name = "key-auth", config = {key_names={"apikey"}}, __api = 1 },
          { name = "key-auth", config = {key_names={"apikey"}}, __api = 2 }
        }
      }

      local inserted_fixtures = faker:insert_from_table(fixtures)

      for type, entities in pairs(inserted_fixtures) do
        for i, entity in ipairs(entities) do
          -- assert object has been inserted
          local entity = inserted_fixtures[type][i]
          assert.truthy(entity)

          -- discover if this entity had any hard-coded relation
          for _, v in ipairs(ENTITIES_TYPES) do
            local has_relation = entity["__"..v] ~= nil
            if has_relation then
              -- check the relation was respected
              assert.truthy(entity[v.."_id"])
            end
          end
        end
      end
    end)

  end)
end)
