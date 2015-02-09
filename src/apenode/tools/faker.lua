local Object = require "classic"
local inspect = require "inspect"

math.randomseed(os.time())

-------------
-- PRIVATE --
-------------

-- Throw an error from a string or table object
-- @param {table|string} The error to throw (will be converted to string if is table)
local function throw(err)
  local err_str
  if type(err) == "table" then
    err_str = inspect(err)
  else
    err_str = err
  end

  error(err_str)
end

-- Gets a random elements from an array
-- @param {table} t Array to get an element from
-- @return A random element
local function random_from_table(t)
  if not t then return {} end

  return t[math.random(#t)]
end

-----------
-- Faker --
-----------

local Faker = Object:extend()

function Faker:new(dao_factory)
  self.dao_factory = dao_factory

  self.inserted_entities = {}
end

function Faker:fake_entity(type, invalid)
  local r = math.random(1, 1000000000)

  if type == "api" then
    local name
    if invalid then
      name = 123456
    else
      name = "random"..r
    end

    return {
      name = name,
      public_dns = "random"..r..".com",
      target_url = "http://random"..r..".com"
    }
  elseif type == "account" then
    local provider_id
    if invalid then
      provider_id = "provider_123"
    else
      provider_id = "random_provider_id_"..r
    end

    return {
      provider_id = provider_id
    }
  elseif type == "application" then
    return {
      account_id = random_from_table(self.inserted_entities.account).id,
      public_key = "public_random"..r,
      secret_key = "private_random"..r
    }
  elseif type == "metric" then
    return {
      api_id = random_from_table(self.inserted_entities.api).id,
      identifier = "127.0.0.1",
      periods = { "second", "minute", "hour" }
    }
  elseif type == "plugin" then
    local type = random_from_table({ "authentication", "ratelimiting" })
    local value = {}
    if type == "authentication" then
      value = { authentication_type = "query", authentication_key_names = { "apikey"..r }}
    else
      value = { period = "minute", limit = r }
    end
    return {
      name = type,
      value = value,
      api_id = random_from_table(self.inserted_entities.api).id,
      application_id = random_from_table(self.inserted_entities.application).id
    }
  else
    throw("Entity of type "..type.." cannot be genereated.")
  end
end

function Faker:seed(random, amount)
  -- amount is optional
  if not amount then amount = 10000 end

  local entities_to_insert = {
    api = {
      { name = "test",  public_dns = "test.com",  target_url = "http://httpbin.org" },
      { name = "test2", public_dns = "test2.com", target_url = "http://httpbin.org" },
      { name = "test3", public_dns = "test3.com", target_url = "http://httpbin.org" },
      { name = "test4", public_dns = "test4.com", target_url = "http://httpbin.org" },
      { name = "test5", public_dns = "test5.com", target_url = "http://httpbin.org" },
      { name = "test6", public_dns = "test6.com", target_url = "http://httpbin.org" }
    },
    account = {
      { provider_id = "provider_123" },
      { provider_id = "provider_124" }
    },
    application = {
      { public_key = "user122", secret_key = "apikey122", __account = 1 },
      { public_key = "user123", secret_key = "apikey123", __account = 1 },
      { public_key = "user124", secret_key = "apikey124", __account = 1 },
    },
    metric = {
      { identifier = "127.0.0.1", periods = { "second", "minute", "hour" }, __api = 1 },
      { identifier = "127.0.0.1", periods = { "second", "minute" }, __api = 1 },
    },
    plugin = {
      { name = "authentication", value = { authentication_type = "query", authentication_key_names = { "apikey" }}, __api = 1 },
      { name = "authentication", value = { authentication_type = "query", authentication_key_names = { "apikey" }}, __api = 6 },
      { name = "authentication", value = { authentication_type = "header", authentication_key_names = { "apikey" }}, __api = 2 },
      { name = "authentication", value = { authentication_type = "basic" }, __api = 3 },
      { name = "ratelimiting",   value = { period = "minute", limit = 2 },  __api = 5 },
      { name = "ratelimiting",   value = { period = "minute", limit = 2 },  __api = 6 },
      { name = "ratelimiting",   value = { period = "minute", limit = 4 }, __api = 6, __application = 3 }
    }
  }

  self:insert_from_table(entities_to_insert)

  if random then
    -- If we ask for random entities, add as many random entities to another table
    -- as the difference between total amount requested and hard-coded ones
    -- If we ask for 1000 entities, we'll have (1000 - number_of_hard_coded) random entities
    local random_entities = {}
    for type, entities in pairs(entities_to_insert) do
      number_to_insert = amount - #entities
      random_entities[type] = {}
      for i = 1, number_to_insert do
        table.insert(random_entities[type], Faker.fake_entity(type))
      end
    end

    self:insert_from_table(random_entities, true)
  end
end

-- Insert entities in the DB using the DAO
-- First accounts and APIs, then the rest which needs references to created accounts and APIs
-- @param {table} entities_to_insert A table with the same structure as the one defined in :seed
-- @param {boolean} random If true, will force applications, plugins and metrics to have relations by choosing
--                         a random entity.
function Faker:insert_from_table(entities_to_insert, random)
  -- Insert in order (for foreign relashionships)
  -- 1. accounts and APIs
  -- 2. applications, plugins and metrics which need refereces to inserted apis and accounts
  for _, type in ipairs({ "api", "account", "application", "plugin", "metric" }) do
    for i, entity in ipairs(entities_to_insert[type]) do
      if not random then
        local foreign_api = entities_to_insert.api[entity.__api]
        local foreign_account = entities_to_insert.account[entity.__account]
        local foreign_application = entities_to_insert.application[entity.__application]

        -- Clean this up otherwise won't pass schema validation
        entity.__api = nil
        entity.__account = nil
        entity.__application = nil

        -- Hard-coded foreign relationships
        if type == "application" then
          if foreign_account then entity.account_id = foreign_account.id end
        elseif type == "plugin" then
          if foreign_api then entity.api_id = foreign_api.id end
          if foreign_application then entity.application_id = foreign_application.id end
        elseif type == "metric" then
          if foreign_api then entity.api_id = foreign_api.id end
        end
      end

      -- Insert in DB
      local res, err

      if type == "metric" then
        res, err = self.dao_factory[type.."s"]:increment(entity.api_id, entity.identifier, entity.periods)
      else
        res, err = self.dao_factory[type.."s"]:insert(entity)
      end

      if err then
        throw("Failed to insert "..type.." entity: "..inspect(entity).."\n"..inspect(err))
      end

      -- For other hard-coded entities relashionships
      entities_to_insert[type][i] = res

      -- For generated fake_entities
      if not self.inserted_entities[type] then
        self.inserted_entities[type] = {}
      end

      table.insert(self.inserted_entities[type], res)
    end
  end
end

return Faker
