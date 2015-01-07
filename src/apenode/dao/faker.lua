math.randomseed(os.time())

local _M = {}

function _M.fake_entity(type, invalid)
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
  end
end

function _M.populate(factory, random, amount)
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
        account_id = 1,
        secret_key = "apikey123"
      },
      {
        account_id = 1,
        public_key = "user123",
        secret_key = "apikey123"
      }
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
      }
    }
  }

  if random then
    if not amount then amount = 1000 end
    for k,v in pairs(entities_to_insert) do
      number_to_insert = amount - #v
      for i = 1, number_to_insert do
        table.insert(v, _M.fake_entity(k))
      end
    end
  end

  for _,api in ipairs(entities_to_insert.api) do
    factory.apis:insert_or_update(api)
  end

  for _,account in ipairs(entities_to_insert.account) do
    factory.accounts:insert_or_update(account)
  end

  for _,application in ipairs(entities_to_insert.application) do
    factory.applications:insert_or_update(application)
  end

  for _,plugin in ipairs(entities_to_insert.plugin) do
    factory.plugins:insert_or_update(plugin)
  end

  for _,metric in ipairs(entities_to_insert.metric) do
    factory.metrics:increment(metric.api_id, metric.application_id, metric.name, metric.timestamp, metric.value)
  end
end

return _M
