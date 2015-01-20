local Object = require "classic"

math.randomseed(os.time())

local function random_from_array(arr)
  return arr[math.random(#arr)]
end

local Faker = Object:extend()

function Faker:new(dao)
  self.dao = dao
end

function Faker.fake_entity(type, invalid)
  local r = math.random(1, 1000000000)

  if type == "api" then
    local name
    if invalid then name = "test" else name = "random"..r end
    return {
      name = name,
      public_dns = "random"..r..".com",
      target_url = "http://random"..r..".com"
    }
  elseif type == "account" then
    local provider_id
    if invalid then provider_id = "provider_123" else provider_id = "random_provider_id_"..r end
    return {
      provider_id = provider_id
    }
  elseif type == "application" then
    return {
      account_id = 1,
      public_key = "random"..r,
      secret_key = "random"..r,
    }
  elseif type == "metric" then
    return {
      api_id = 1,
      application_id = 1,
      name = "requests",
      value = r,
      timestamp = r
    }
  elseif type == "plugin" then
    return {
      api_id = r,
      name = "random"..r,
      value = {
        authentication_type = "query",
        authentication_key_names = { "apikey" }
      }
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
      {
        name = "test",
        public_dns = "test.com",
        target_url = "http://httpbin.org"
      },
      {
        name = "test2",
        public_dns = "test2.com",
        target_url = "http://httpbin.org"
      },
      {
        name = "test3",
        public_dns = "test3.com",
        target_url = "http://httpbin.org"
      },
      {
        name = "test4",
        public_dns = "test4.com",
        target_url = "http://httpbin.org"
      },
      {
        name = "test5",
        public_dns = "test5.com",
        target_url = "http://httpbin.org"
      },
      {
        name = "test6",
        public_dns = "test6.com",
        target_url = "http://httpbin.org"
      }
    },
    account = {
      {
        provider_id = "provider_123"
      }
    },
    application = {
      {
        secret_key = "apikey123"
      },
      {
        public_key = "user123",
        secret_key = "apikey123"
      },
      {
        secret_key = "apikey124"
      },
    },
    metric = {
      {
        api_id = 1,
        application_id = 1,
        name = "requests",
        value = 0,
        timestamp = 123
      },
      {
        api_id = 1,
        application_id = 1,
        name = "requests",
        value = 0,
        timestamp = 123456
      }
    },
    plugin = {
      {
        api_id = 1,
        name = "authentication",
        value = {
          authentication_type = "query",
          authentication_key_names = { "apikey" }
        }
      },
      {
        api_id = 2,
        name = "authentication",
        value = {
          authentication_type = "header",
          authentication_key_names = { "apikey" }
        }
      },
      {
        api_id = 3,
        name = "authentication",
        value = {
          authentication_type = "basic"
        }
      },
      {
        api_id = 6,
        name = "authentication",
        value = {
          authentication_type = "query",
          authentication_key_names = { "apikey" }
        }
      },
      {
        api_id = 5,
        name = "ratelimiting",
        value = {
          period = "minute",
          limit = 2
        }
      },
      {
        api_id = 6,
        name = "ratelimiting",
        value = {
          period = "minute",
          limit = 2
        }
      },
      {
        api_id = 6,
        application_id = 3,
        name = "ratelimiting",
        value = {
          period = "minute",
          limit = 4
        }
      }
    }
  }

  if random then
    for k,v in pairs(entities_to_insert) do
      number_to_insert = amount - #v
      for i = 1, number_to_insert do
        printl(v, i)
        table.insert(v, Faker.fake_entity(k))
      end
    end
  end

  -- Reference to entities used in compsite keys
  local inserted_apis, inserted_accounts, inserted_applications = {}, {}, {}

  for _,api in ipairs(entities_to_insert.api) do
    local res, err = self.dao.apis:insert_or_update(api)
    if err then error(err) end

    table.insert(inserted_apis, res)
  end

  for _,account in ipairs(entities_to_insert.account) do
    local res, err = self.dao.accounts:insert_or_update(account)
    if err then error(err) end

    table.insert(inserted_accounts, res)
  end

  for _,application in ipairs(entities_to_insert.application) do
    application.account_id = random_from_array(inserted_accounts).id

    local res, err = self.dao.applications:insert_or_update(application)
    if err then error(err) end

    table.insert(inserted_applications, res)
  end

  for _,plugin in ipairs(entities_to_insert.plugin) do
    plugin.api_id = random_from_array(inserted_apis).id
    plugin.application_id = random_from_array(inserted_applications).id

    local res, err = self.dao.plugins:insert_or_update(plugin)
    if err then error(err) end
  end

  for _,metric in ipairs(entities_to_insert.metric) do
    metric.api_id = random_from_array(inserted_apis).id
    metric.application_id = random_from_array(inserted_applications).id

    local res, err = self.dao.metrics:increment(metric.api_id, metric.application_id, metric.name, metric.timestamp, metric.value)
    if err then error(err) end
  end
end

return Faker
