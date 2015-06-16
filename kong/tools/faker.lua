local Object = require "classic"

local Faker = Object:extend()

function Faker:new(dao_factory)
  self.dao_factory = dao_factory
end

-- Generate a fake entity.
-- @param `type`  Type of the entity to generate.
-- @return        An valid entity (a table) complying to the defined schema.
function Faker:fake_entity(type)
  local r = math.random(1, 1000000000)

  if type == "api" then
    return {
      name = "random"..r,
      public_dns = "random"..r..".com",
      target_url = "http://random"..r..".com"
    }
  elseif type == "consumer" then
    return {
      custom_id = "random_custom_id_"..r
    }
  elseif type == "plugin_configuration" then
    return {
      name = "keyauth",
      value = { key_names = {"apikey"} }
    }
  else
    error("Entity of type "..type.." cannot be generated.")
  end
end

-- Seed the database with random APIs and Consumers.
-- @param {number} random_amount The number of random entities to add (apis, consumers, applications)
function Faker:seed(random_amount)
  if not random_amount then random_amount = 0 end

  local random_entities = {}

  for _, type in ipairs({ "api", "consumer" }) do
    random_entities[type] = {}
    for i = 1, random_amount do
      table.insert(random_entities[type], self:fake_entity(type))
    end
  end

  return self:insert_from_table(random_entities)
end

-- Insert entities in the DB using the DAO.
-- @param `entities_to_insert` A table with the same structure as the one defined in `:seed()`
function Faker:insert_from_table(entities_to_insert)
  local inserted_entities = {}

  -- Insert in order (for foreign relashionships)
  -- 1. consumers and APIs
  -- 2. credentials, which need references to inserted apis and consumers
  for _, type in ipairs({ "api", "consumer", "basicauth_credential", "keyauth_credential", "plugin_configuration" }) do
    if entities_to_insert[type] then
      for i, entity in ipairs(entities_to_insert[type]) do

        if entity.__api or entity.__consumer then
          local foreign_api = entities_to_insert.api and entities_to_insert.api[entity.__api]
          local foreign_consumer = entities_to_insert.consumer and entities_to_insert.consumer[entity.__consumer]

          -- Clean this up otherwise won't pass schema validation
          entity.__api = nil
          entity.__consumer = nil

          if foreign_api then entity.api_id = foreign_api.id end
          if foreign_consumer then entity.consumer_id = foreign_consumer.id end
        end

        -- Insert in DB
        local dao_type = type == "plugin_configuration" and "plugins_configurations" or type.."s"
        local res, err = self.dao_factory[dao_type]:insert(entity)
        if err then
          local printable_mt = require "kong.tools.printable"
          setmetatable(entity, printable_mt)
          error("Faker failed to insert "..type.." entity: "..entity.."\n"..err)
        end

        -- For other hard-coded entities relashionships
        entities_to_insert[type][i] = res

        if not inserted_entities[type] then
          inserted_entities[type] = {}
        end

        table.insert(inserted_entities[type], res)
      end
    end
  end

  return inserted_entities
end

return Faker
