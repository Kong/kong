local Object = require "classic"

math.randomseed(os.time())

local function random_from_table(t)
  return t[math.random(#t)]
end

local Faker = Object:extend()

function Faker:new(dao)
  self.dao = dao
end

function Faker.fake_entity(type, invalid)
  local r = math.random(1, 1000000000)

  if type == "api" then
    local name
    if invalid then
      name = "test"
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
    return {
      name = "random"..r,
      value = { authentication_type = "query", authentication_key_names = { "apikey" }}
    }
  else
    error("Model of type "..type.." cannot be genereated.")
  end
end

function Faker:seed(random, amount)
  -- amount is optional
  if not amount then amount = 1000 end

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
      { secret_key = "apikey123", __account = 1 },
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
    for k, v in pairs(entities_to_insert) do
      number_to_insert = amount - #v
      random_entities[k] = {}
      for i = 1, number_to_insert do
        table.insert(random_entities[k], Faker.fake_entity(k))
      end
    end

    self:insert_from_table(random_entities)
  end
end

-- Insert entities in the DB using the DAO
-- First accounts and APIs, then the rest which needs references to created accounts and APIs
-- @param table entities_to_insert A table with the same structure as the one defined in :seed
function Faker:insert_from_table(entities_to_insert)
  -- 1. Insert accounts and APIs
  for type, entities in pairs { apis = entities_to_insert.api,
                                accounts = entities_to_insert.account } do
    for i,entity in ipairs(entities) do
      local res, err = self.dao[type]:insert_or_update(entity)

      if err then error(err) end
      entities[i] = res
    end
  end

  -- 2. Insert applications, plugins and metrics which need refereces to inserted apis and accounts
  for type, entities in pairs { applications = entities_to_insert.application,
                                plugins = entities_to_insert.plugin,
                                metrics = entities_to_insert.metric } do
    for i, entity in ipairs(entities) do
      local res, err
      local api = entities_to_insert.api[entity.__api]
      local account = entities_to_insert.account[entity.__account]
      local application = entities_to_insert.application[entity.__application]
      if not api then
        api = random_from_table(entities_to_insert.api)
      end
      if not application then
        application = random_from_table(entities_to_insert.application)
      end
      if not account then
        account = random_from_table(entities_to_insert.account)
      end

      entity.__api = nil
      entity.__account = nil
      entity.__application = nil

      if type == "applications" then
        entity.account_id = account.id
        res, err = self.dao.applications:insert_or_update(entity)
      elseif type == "plugins" then
        entity.api_id = api.id
        entity.application_id = application.id
        res, err = self.dao.plugins:insert_or_update(entity)
      elseif type == "metrics" then
        res, err = self.dao.metrics:increment(api.id, application.id, entity.origin_ip, entity.name, entity.timestamp, entity.period, entity.value)
      end

      if err then
        error(err)
      end

      entities[i] = res
    end
  end
end

return Faker
