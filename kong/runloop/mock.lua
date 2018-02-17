local cjson            = require "cjson.safe"
local singletons       = require "kong.singletons"
local plugins_iterator = require "kong.runloop.plugins_iterator"
local constants        = require "kong.constants"
local responses        = require "kong.tools.responses"
local utils            = require "kong.tools.utils"
local public           = require "kong.tools.public"
local BasePlugin       = require "kong.plugins.base_plugin"


local ngx              = ngx
local null             = ngx.null
local type             = type
local next             = next
local ipairs           = ipairs
local insert           = table.insert
local tostring         = tostring


local function set_context(ctx, name)
  local item = ctx[name]
  if item and next(item) then
    ctx.mock[name] = item

  else
    ctx.mock[name] = null
  end
end


local mock = {}


function mock.consumer(ctx)
  local consumer_id

  local args = ngx.req.get_uri_args()
  if args then
    consumer_id = args.consumer
    if type(consumer_id) == "table" then
      consumer_id = consumer_id[1]
    end
  end

  if not consumer_id then
    ngx.req.read_body()

    args = public.get_body_args()
    if args then
      consumer_id = args.consumer
      if type(consumer_id) == "table" then
        consumer_id = consumer_id[1]
      end
    end
  end

  if consumer_id then
    local consumer

    if type(consumer_id) == "string" or type(consumer_id) == "number" then
      consumer_id = tostring(consumer_id)

      if utils.is_valid_uuid(consumer_id) then
        local consumer_cache_key = singletons.dao.consumers:cache_key(consumer_id)
        consumer = singletons.cache:get(
          consumer_cache_key,
          nil,
          function(consumer_id)
            return singletons.dao.consumers:find { id = consumer_id }
          end,
          consumer_id)

      else
        local result = singletons.dao.consumers:find_all { username = consumer_id }
        if type(result) == "table" and type(result[1]) == "table" then
          consumer =  result[1]
        end

        if not consumer then
          result = singletons.dao.consumers:find_all { custom_id = consumer_id }
          if type(result) == "table" and type(result[1]) == "table" then
            consumer = result[1]
          end
        end
      end
    end

    if consumer then
      -- TODO: this needs to be abstracted away
      ctx.authenticated_consumer   = consumer
      ctx.authenticated_credential = {
        consumer_id = consumer.id
      }

      ngx.req.set_header(constants.HEADERS.CONSUMER_ID,        consumer.id)
      ngx.req.set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
      ngx.req.set_header(constants.HEADERS.CONSUMER_USERNAME,  consumer.username)

    else
      return responses.send_HTTP_BAD_REQUEST("consumer not found")
    end
  end
end


function mock.address(any)
  local configuration = singletons.configuration

  if any or ngx.var.upstream_scheme == "https" then
    for _, proxy_server in ipairs(configuration.proxy_servers) do
      if proxy_server.mock then
        for _, listener in ipairs(proxy_server.listeners) do
          if any or listener.ssl then
            return listener.ip, listener.port
          end
        end
      end
    end
  end

  if not any then
    return mock.address(true)
  end
end


function mock.plugins(ctx, loaded_plugins, phase)
  local data    = ctx.mock     or {}
  local plugins = data.plugins or {}
  local phase   = phase        or ngx.get_phase()

  for plugin, plugin_conf in plugins_iterator(loaded_plugins, phase == "rewrite" or phase == "access") do
    if plugin.handler[phase] ~= BasePlugin[phase] then
      insert(plugins, {
        name        = plugin.handler._name,
        version     = plugin.handler.VERSION,
        priority    = plugin.handler.PRIORITY,
        no_consumer = plugin.schema.no_consumer,
        phase       = phase,
        config      = plugin_conf,
      })
    end
  end

  data.plugins = plugins
  ctx.mock     = data
end


function mock.data(ctx)
  set_context(ctx, "api")
  set_context(ctx, "service")
  set_context(ctx, "route")
  set_context(ctx, "router_matches")
  set_context(ctx, "balancer_data")
  set_context(ctx, "authenticated_consumer")
  set_context(ctx, "authenticated_credential")
end


function mock.access(ctx, loaded_plugins)
  local var = ngx.var

  var.upstream_scheme = var.scheme
  var.upstream_uri    = "/kong_mock_handler"

  mock.consumer(ctx)
  mock.plugins(ctx, loaded_plugins)
  mock.data(ctx)
end


function mock.header_filter(ctx, loaded_plugins)
  if not ctx.KONG_PROXIED then
    return
  end

  mock.plugins(ctx, loaded_plugins)

  ngx.header.content_length = nil
  ngx.header.content_type   = "application/json"
end


function mock.body_filter(ctx, loaded_plugins)
  if not ctx.KONG_PROXIED then
    return
  end

  mock.plugins(ctx, loaded_plugins)

  local data = ctx.mock

  if ngx.arg[2] then
    mock.plugins(ctx, "log")
    ngx.arg[1] = cjson.encode(data)

  else
    ngx.arg[1] = nil
  end
end


mock.rewrite       = mock.plugins
mock.ssl_certicate = mock.plugins
mock.log           = function() end


return mock
