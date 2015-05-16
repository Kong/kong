local Object = require "classic"
local utils = require "kong.tools.utils"

math.randomseed(os.time())

-- Return a random element from an array.
-- @param `t` Array to get an element from.
-- @return    A random element from the `t` array.
local function random_from_table(t)
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
    -- TESTS APIs
    { name = "API TESTS 1", public_dns = "test1.com", target_url = "http://mockbin.com" },
    { name = "API TESTS 2", public_dns = "test2.com", target_url = "http://mockbin.com" },
    { name = "API TESTS 3", public_dns = "test3.com", target_url = "http://mockbin.com" },
    { name = "API TESTS 4", public_dns = "test4.com", target_url = "http://mockbin.com" },
    { name = "API TESTS 5", public_dns = "test5.com", target_url = "http://mockbin.com" },
    { name = "API TESTS 6", public_dns = "cors1.com", target_url = "http://mockbin.com" },
    { name = "API TESTS 7", public_dns = "cors2.com", target_url = "http://mockbin.com" },
    { name = "API TESTS 8 (logging)", public_dns = "logging.com", target_url = "http://mockbin.com" },

    { name = "API TESTS 8 (dns)", public_dns = "dns1.com", target_url = "http://127.0.0.1:7771" },
    { name = "API TESTS 9 (dns)", public_dns = "dns2.com", target_url = "http://localhost:7771" },

    { name = "API TESTS 10 (ssl)", public_dns = "localhost", target_url = "http://mockbin.com" },

    -- DEVELOPMENT APIs. Please do not use those in tests
    { name = "API DEV 1", public_dns = "dev.com", target_url = "http://mockbin.com" },
  },
  consumer = {
    { custom_id = "provider_123" },
    { custom_id = "provider_124" }
  },
  plugin_configuration = {
    -- API 1
    { name = "keyauth", value = { key_names = { "apikey" }}, __api = 1 },
    -- API 2
    { name = "basicauth", value = {}, __api = 2 },
    -- API 3
    { name = "keyauth", value = {key_names = {"apikey"}, hide_credentials = true}, __api = 3 },
    { name = "ratelimiting", value = {period = "minute", limit = 6}, __api = 3 },
    { name = "ratelimiting", value = {period = "minute", limit = 8}, __api = 3, __consumer = 1 },
    -- API 4
    { name = "ratelimiting", value = {period = "minute", limit = 6}, __api = 4 },
    -- API 5
    { name = "request_transformer", value = {
      add = { headers = {"x-added:true", "x-added2:true" },
              querystring = {"newparam:value"},
              form = {"newformparam:newvalue"} },
      remove = { headers = { "x-to-remove" },
                 querystring = { "toremovequery" },
                 form = { "toremoveform" } } }, __api = 5 },
    -- API 6
    { name = "cors", value = {}, __api = 6 },
    -- API 7
    { name = "cors", value = { origin = "example.com",
                               methods = "GET",
                               headers = "origin, type, accepts",
                               exposed_headers = "x-auth-token",
                               max_age = 23,
                               credentials = true }, __api = 7 },
    -- API 8
    { name = "tcplog", value = { host = "127.0.0.1", port = 7777 }, __api = 8 },
    { name = "udplog", value = { host = "127.0.0.1", port = 8888 }, __api = 8 },
    { name = "filelog", value = {}, __api = 8 },
    -- API 10
    { name = "ssl", value = { cert = [[
-----BEGIN CERTIFICATE-----
MIICUTCCAboCCQDmzZoyut/faTANBgkqhkiG9w0BAQsFADBtMQswCQYDVQQGEwJV
UzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwNU2FuIEZyYW5jaXNjbzEQ
MA4GA1UECgwHTWFzaGFwZTELMAkGA1UECwwCSVQxEjAQBgNVBAMMCWxvY2FsaG9z
dDAeFw0xNTA1MTUwMDA4MzZaFw0xNjA1MTQwMDA4MzZaMG0xCzAJBgNVBAYTAlVT
MRMwEQYDVQQIDApDYWxpZm9ybmlhMRYwFAYDVQQHDA1TYW4gRnJhbmNpc2NvMRAw
DgYDVQQKDAdNYXNoYXBlMQswCQYDVQQLDAJJVDESMBAGA1UEAwwJbG9jYWxob3N0
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDDG3WEFIeL8YWyEaJ0L3QESzR9
Epg9d2p/y1v0xQgrwkM6sRFX81oNGdXssOeXAHJM6BXmMSbhfC+i3AkRPloltnwl
yEylOBaGY0GlPehZ9x+UxDiNpnjDakWWqXoFn1vDAU8gLTmduGVIGsQxT32sF0Y9
pFnbNQ0lU6cRe3/n8wIDAQABMA0GCSqGSIb3DQEBCwUAA4GBAHpVwlC75/LTKepa
VKHXqpk5H1zYsj2byBhYOY5/+aYbNqfa2DaWE1zwv/J4E7wgKaeQHHgT2XBtYSRM
ZMG9SgECUHZ+A/OebWgSfZvXbsIZ+PLk46rlZQ0O73kkbAyMTGNRvfEPeDmw0TR2
DYk+jZoTdElBV6PQAxysILNeJK5n
-----END CERTIFICATE-----
]], key = [[
-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQDDG3WEFIeL8YWyEaJ0L3QESzR9Epg9d2p/y1v0xQgrwkM6sRFX
81oNGdXssOeXAHJM6BXmMSbhfC+i3AkRPloltnwlyEylOBaGY0GlPehZ9x+UxDiN
pnjDakWWqXoFn1vDAU8gLTmduGVIGsQxT32sF0Y9pFnbNQ0lU6cRe3/n8wIDAQAB
AoGAdQQhBShy60Hd16Cv+FMFmBWq02C1ohfe7ep/qlwJvIT0YV0Vc9RmK/lUznKD
U5NW+j0v9TGBijc7MsgZQBhPY8aQXmwPfgaLq3YXjNJUITGwH0KAZe9WBiLObVZb
MDoa349PrjSpAkDryyF2wCmRBphUePd9BVeV/CR/a78BvSECQQDrWT2fqHjpSfKl
rjt9n29fWbj2Sfjkjaa+MK1l4tgDAVrfNLjsf6aXTBbSUWaTfpHG9E6frTMuE5pT
BcJf3TJJAkEA1DpBjavo8zpzjgmQ5SESrNB3+BYZYH9JRI91eIZYQzIvRgVRP+yG
vc0Hdhr1xSwN8XiFcVm24s5TEM+uE+bIWwJAQ24BKvJhGi4WuIOQBfEdPst9JAuT
pSA0qv9VXwC8dTf5KkR3y0LTnzusujuaUR4NdFxg/nzoUgZJzAm1ZDQDCQJBAKmq
sUG70A60CjHhv+8Ok8mJGIBD2qHk4QRo1Hc4oFOISXbnRV+fjtEqmu52+0lYwQTt
X3GRUb7dSFdGUVsjw8UCQH1sEtryRFIeCJgLT2p+UPYMNr6f/QYzpiK/M61xe2yf
IN2a44ptbkUjN8U0WeTGMBP/XfK3SvV6wAKAE3cDB2c=
-----END RSA PRIVATE KEY-----
]] }, __api = 10 }
  },
  -- TODO: remove plugins from core
  keyauth_credential = {
    { key = "apikey122", __consumer = 1 },
    { key = "apikey123", __consumer = 2 }
  },
  basicauth_credential = {
    { username = "username", password = "password", __consumer = 1 }
  }
}

-- Generate a fake entity
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
    -- TODO: remove plugins from core
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

-- Insert entities in the DB using the DAO.
-- @param `entities_to_insert` A table with the same structure as the one defined in `:seed()`
-- @param `pick_relations`     If true, will pick relations from the __ properties (see fixtures)
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
        local printable_mt = require "kong.tools.printable"
        setmetatable(entity, printable_mt)
        error("Faker failed to insert "..type.." entity: "..entity.."\n"..err)
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
