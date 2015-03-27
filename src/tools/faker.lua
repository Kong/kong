local Object = require "classic"
local inspect = require "inspect"
local utils = require "kong.tools.utils"

math.randomseed(os.time())

-- Return a random elements from an array
-- @param {table} t Array to get an element from
-- @return A random element
local function random_from_table(t, remove)
  if not t then return {} end
  return t[math.random(#t)]
end

--
-- Faker
--
local Faker = Object:extend()

function Faker:new(dao_factory)
  self.dao_factory = dao_factory
  self.inserted_entities = {}
end

Faker.FIXTURES = {
  api = {
    { name = "test",  public_dns = "test.com",  target_url = "http://mockbin.com" },
    { name = "test2", public_dns = "test2.com", target_url = "http://mockbin.com" },
    { name = "test3", public_dns = "test3.com", target_url = "http://mockbin.com" },
    { name = "test4", public_dns = "test4.com", target_url = "http://mockbin.com" },
    { name = "test5", public_dns = "test5.com", target_url = "http://mockbin.com" },
    { name = "test6", public_dns = "test6.com", target_url = "http://mockbin.com" }
  },
  consumer = {
    { custom_id = "provider_123" },
    { custom_id = "provider_124" }
  },
  keyauth_credential = {
    { key = "apikey122", __consumer = 1 },
    { key = "apikey123", __consumer = 2 }
  },
  basicauth_credential = {
    { username = "username", password = "password", __consumer = 1 },
  },
  plugin_configuration = {
    { name = "keyauth", value = { key_names = { "apikey" }}, __api = 1 },
    { name = "keyauth", value = { key_names = { "apikey" }}, __api = 6 },
    { name = "keyauth", value = { key_names = { "apikey" }}, __api = 2 },
    { name = "basicauth", value = {}, __api = 3 },
    { name = "ratelimiting", value = { period = "minute", limit = 2 }, __api = 5 },
    { name = "ratelimiting", value = { period = "minute", limit = 2 }, __api = 6 },
    { name = "ratelimiting", value = { period = "minute", limit = 4 }, __api = 6, __consumer = 1 },
    { name = "tcplog", value = { host = "127.0.0.1", port = 7777 }, __api = 1 },
    { name = "udplog", value = { host = "127.0.0.1", port = 8888 }, __api = 1 },
    { name = "filelog", value = { }, __api = 1 }
  }
}

-- Generate a fake entity
-- @param {string} type Type of the entity to generate
-- @return {table} An entity schema
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
  elseif type == "basicauth_credential" then
    return {
      consumer_id = random_from_table(self.inserted_entities.consumer).id,
      username = "username_random"..r,
      password = "password_random"..r
    }
  elseif type == "keyauth_credential" then
    return {
      consumer_id = random_from_table(self.inserted_entities.consumer).id,
      key = "key_random"..r
    }
  elseif type == "plugin_configuration" then
    local plugin_type = random_from_table({ "keyauth", "ratelimiting" })
    local plugin_value
    if plugin_type == "keyauth" then
      plugin_value = { key_names = { "apikey"..r }}
    else
      plugin_value = { period = "minute", limit = r }
    end
    return {
      name = plugin_type,
      value = plugin_value,
      api_id = nil,
      consumer_id = nil
    }
  else
    error("Entity of type "..type.." cannot be generated.")
  end
end

-- Seed the database with a set of hard-coded entities, and optionally random data
-- @param {number} random_amount The number of random entities to add (apis, consumers, applications)
function Faker:seed(random_amount)
  -- reset previously inserted entities
  self.inserted_entities = {}

  self:insert_from_table(utils.deepcopy(Faker.FIXTURES), true)

  if random_amount then
    -- If we ask for random entities, add as many random entities to another table
    -- as the difference between total amount requested and hard-coded ones
    -- If we ask for 1000 entities, we'll have (1000 - number_of_hard_coded) random entities
    --
    -- We don't generate any random plugin configuration
    local random_entities = {}
    for type, entities in pairs(Faker.FIXTURES) do
      random_entities[type] = {}
      if type ~= "plugin_configuration" then
        for i = 1, random_amount do
          table.insert(random_entities[type], self:fake_entity(type))
        end
      end
    end

    self:insert_from_table(random_entities)
  end
end

-- Insert entities in the DB using the DAO
-- First consumers and APIs, then the rest which needs references to created consumers and APIs
-- @param {table} entities_to_insert A table with the same structure as the one defined in :seed
-- @param {boolean} pick_relations If true, will pick relations from the __ property
function Faker:insert_from_table(entities_to_insert, pick_relations)
  -- Insert in order (for foreign relashionships)
  -- 1. consumers and APIs
  -- 2. credentials, which need refereces to inserted apis and consumers
  for _, type in ipairs({ "api", "consumer", "basicauth_credential", "keyauth_credential", "plugin_configuration" }) do
    for i, entity in ipairs(entities_to_insert[type]) do

      if pick_relations then
        local foreign_api = entities_to_insert.api[entity.__api]
        local foreign_consumer = entities_to_insert.consumer[entity.__consumer]

        -- Clean this up otherwise won't pass schema validation
        entity.__api = nil
        entity.__consumer = nil

        -- Hard-coded foreign relationships
        if type == "basicauth_credential" then
          if foreign_consumer then
            entity.consumer_id = foreign_consumer.id
          end
        elseif type == "keyauth_credential" then
          if foreign_consumer then
            entity.consumer_id = foreign_consumer.id
          end
        elseif type == "plugin_configuration" then
          if foreign_api then entity.api_id = foreign_api.id end
          if foreign_consumer then entity.consumer_id = foreign_consumer.id end
        end
      end

      -- Insert in DB
      local dao_type = type=="plugin_configuration" and "plugins_configurations" or type.."s"
      local res, err = self.dao_factory[dao_type]:insert(entity)
      if err then
        error("Faker failed to insert "..type.." entity: "..inspect(entity).."\n"..err)
      end

      -- For other hard-coded entities relashionships
      entities_to_insert[type][i] = res

      -- For generated fake_entities to fetch the relations they need
      if not self.inserted_entities[type] then
        self.inserted_entities[type] = {}
      end

      table.insert(self.inserted_entities[type], res)
    end
  end
end

return Faker
