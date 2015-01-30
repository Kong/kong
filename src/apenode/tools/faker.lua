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
  return t[math.random(#t)]
end

-----------
-- Faker --
-----------

local Faker = Object:extend()

function Faker:new(dao_factory)
  self.dao_factory = dao_factory
end

function Faker.fake_entity(type, invalid)
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
      public_key = "random"..r,
      secret_key = "random"..r
    }
  elseif type == "metric" then
    return {
      name = "requests",
      value = r,
      period = "second",
      timestamp = r
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
      value = value
    }
  else
    throw("Model of type "..type.." cannot be genereated.")
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
      { provider_id = "provider_123" }
    },
    application = {
      { secret_key = "apikey122", __account = 1 },
      { public_key = "user123", secret_key = "apikey123", __account = 1 },
      { secret_key = "apikey124", __account = 1 },
    },
    metric = {
      { name = "requests", value = 0, timestamp = 123, period = "second", __api = 1, __application = 1 },
      { name = "requests", value = 0, timestamp = 123456, period = "second", __api = 1, __application = 1 }
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
-- @param table entities_to_insert A table with the same structure as the one defined in :seed
-- @param boolean random If true, will force applications, plugins and metrics to have relations by choosing
--                       a random entity.
function Faker:insert_from_table(entities_to_insert, random)
  -- 1. Insert accounts and APIs
  for type, entities in pairs({ apis = entities_to_insert.api,
                                accounts = entities_to_insert.account }) do
    for i, entity in ipairs(entities) do
      local res, err = self.dao_factory[type]:insert(entity)
      if err then
        throw("Failed to insert "..type.." entity: "..inspect(entity).."\n"..inspect(err))
      end

      entities[i] = res
    end
  end

  -- 2. Insert applications, plugins and metrics which need refereces to inserted apis and accounts
  for type, entities in pairs { applications = entities_to_insert.application,
                                plugins = entities_to_insert.plugin } do
    for i, entity in ipairs(entities) do
      local res, err
      local api = entities_to_insert.api[entity.__api]
      local account = entities_to_insert.account[entity.__account]
      local application = entities_to_insert.application[entity.__application]
      if not api and random then
        api = random_from_table(entities_to_insert.api)
      end
      if not application and random then
        application = random_from_table(entities_to_insert.application)
      end
      if not account and random then
        account = random_from_table(entities_to_insert.account)
      end

      entity.__api = nil
      entity.__account = nil
      entity.__application = nil

      if type == "applications" then
        if account then entity.account_id = account.id end
      elseif type == "plugins" then
        if api then entity.api_id = api.id end
        if application then entity.application_id = application.id end
      elseif type == "metrics" then
        if api then entity.api_id = api.id end
        if application then entity.application_id = application.id end
      end

      if type == "metrics" then
        res, err = model_instance:increment_self()
      else
        res, err = self.dao_factory[type]:insert(entity)
      end

      if err then
        throw("Failed to insert "..type.." entity: "..inspect(entity).."\n"..inspect(err))
      end

      entities[i] = res
    end
  end
end

return Faker
