-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants    = require "kong.constants"
local openssl_x509 = require "resty.openssl.x509"
local chain_lib    = require "resty.openssl.x509.chain"

local _M = {}

local kong = kong
local ipairs = ipairs
local new_tab = require("table.new")

local PREFIX_SNIS_PSEUDO_INDEX  = -1
local POSTFIX_SNIS_PSEUDO_INDEX = -2
_M.PREFIX_SNIS_PSEUDO_INDEX = PREFIX_SNIS_PSEUDO_INDEX
_M.POSTFIX_SNIS_PSEUDO_INDEX = POSTFIX_SNIS_PSEUDO_INDEX
local TTL_FOREVER = { ttl = 0 }

local ca_cert_cache_opts = {
  l1_serializer = function(ca)
    local x509, err = openssl_x509.new(ca.cert, "PEM")
    if err then
      return nil, err
    end

    return x509
  end
}


-- make the table out side of function to reuse table
local key = new_tab(1, 0)

local function load_ca(ca_id)
  kong.log.debug("cache miss for CA Cert")

  key.id = ca_id
  local ca, err = kong.db.ca_certificates:select(key)
  if not ca then
    if err then
      return nil, err
    end

    return nil, "CA Certificate '" .. tostring(ca_id) .. "' does not exist"
  end

  return ca
end

local function merge_ca_ids(sni, ca_ids)
  sni.ca_ids = sni.ca_ids or {}
  local sni_ca_ids = sni.ca_ids

  for _, ca_id in ipairs(ca_ids) do
    if not sni_ca_ids[ca_id] then
      sni_ca_ids[ca_id] = true
    end
  end
end

local function ca_cert_cache_key(ca_id)
  return "mtls:cacert:" .. ca_id
end

local function load_routes_from_db(db, route_id, options)
  kong.log.debug("cache miss for route id: " .. route_id.id)
  local routes, err = db.routes:select(route_id, options)
  if routes == nil then
    -- the third value means "do not cache"
    return nil, err, -1
  end

  return routes
end


local function build_snis_for_route(route, snis, send_ca_dn, ca_ids)
  -- every route should have SNI or ask cert on all requests
  if not route.snis or #route.snis == 0 then
    snis["*"] = snis["*"] or {}

    if send_ca_dn then
      merge_ca_ids(snis["*"], ca_ids)
    end

  else
    for _, sni in ipairs(route.snis) do
      local sni_t
      local idx = sni:find("*", 1, true)

      if idx == 1 then
        -- store snis with the leftmost wildcard in a subtable
        snis[POSTFIX_SNIS_PSEUDO_INDEX] = snis[POSTFIX_SNIS_PSEUDO_INDEX] or {}
        local postfix_snis = snis[POSTFIX_SNIS_PSEUDO_INDEX]
        postfix_snis[sni] = postfix_snis[sni] or { value = sni:sub(2) }
        sni_t = postfix_snis[sni]
        kong.log.debug("add a postfix sni ", sni)

      elseif idx == #sni then
        -- store snis with the rightmost wildcard in a subtable
        snis[PREFIX_SNIS_PSEUDO_INDEX] = snis[PREFIX_SNIS_PSEUDO_INDEX] or {}
        local prefix_snis = snis[PREFIX_SNIS_PSEUDO_INDEX]
        prefix_snis[sni] = prefix_snis[sni] or { value = sni:sub(1, -2) }
        sni_t = prefix_snis[sni]
        kong.log.debug("add a prefix sni ", sni)

      else
        snis[sni] = snis[sni] or {}
        sni_t = snis[sni]
        kong.log.debug("add a plain sni ", sni)
      end

      if send_ca_dn then
        merge_ca_ids(sni_t, ca_ids)
      end
    end
  end
end


local function get_snis_for_plugin(db, plugin, snis, options)
  -- plugin applied on service
  local service_pk = plugin.service
  local send_ca_dn = plugin.config.send_ca_dn
  local ca_ids = plugin.config.ca_certificates

  if service_pk then
    for route, err in db.routes:each_for_service(service_pk, nil, options) do
      if err then
        return err
      end

      -- XXX: strictly speaking, if a mtls plugin is also applied on the route,
      -- then we should skip the plugin applied on the corresponding service,
      -- as the plugin on route has a higher priority.
      -- But this requires a plugin iteration on every route.
      -- For performance considerations, we choose to continue.
      -- Sending a few more ca dn is not a big deal, since we are already doing
      -- this by merging the ca dn of mtls plugins with the same sni.
      -- After all, sending some extra ca dn is better than sending nothing.
      build_snis_for_route(route, snis, send_ca_dn, ca_ids)
    end

    return
  end

  -- plugin applied on route
  local route_pk = plugin.route
  if route_pk then
    -- since routes entity is workspaceable, workspace id
    -- needs to be passed when computing cache key
    local cache_key = db.routes:cache_key(route_pk.id, nil, nil, nil, nil, plugin.ws_id)
    local cache_obj = kong[constants.ENTITY_CACHE_STORE.routes]
    local route, err = cache_obj:get(cache_key, TTL_FOREVER,
                                      load_routes_from_db, db,
                                      route_pk, options)

    if err then
      return err
    end

    build_snis_for_route(route, snis, send_ca_dn, ca_ids)

    return
  end

  -- plugin applied on global scope
  snis["*"] = snis["*"] or {}
  if send_ca_dn then
    merge_ca_ids(snis["*"], ca_ids)
  end
end

-- build ca_cert_chain from sni_t
local function build_ca_cert_chain(sni_t)
  local ca_ids = sni_t.ca_ids

  if not ca_ids then
    return true
  end

  local chain, err = chain_lib.new()
  if err then
    return nil, err
  end

  for ca_id, _ in pairs(ca_ids) do
    local x509, err = kong.cache:get(ca_cert_cache_key(ca_id), ca_cert_cache_opts,
                                   load_ca, ca_id)
    if err then
      return nil, err
    end

    local _
    _, err = chain:add(x509)

    if err then
      return nil, err
    end
  end

  sni_t.ca_cert_chain = chain

  return true
end


-- build ca_cert_chain for every sni
function _M.sni_cache_l1_serializer(snis)
  for k, v in pairs(snis) do
    if k == PREFIX_SNIS_PSEUDO_INDEX or
       k == POSTFIX_SNIS_PSEUDO_INDEX then
      for _, sni_t in pairs(v) do
        local res, err = build_ca_cert_chain(sni_t)
        if not res then
          return nil, err
        end
      end

    else
      local res, err = build_ca_cert_chain(v)
      if not res then
        return nil, err
      end
    end
  end

  return snis
end

function _M.build_ssl_route_filter_set(plugin_name)
  kong.log.debug("building ssl route filter set for plugin name " .. plugin_name)
  local db = kong.db
  local snis = {}
  local options = {}

  for plugin, err in kong.db.plugins:each() do
    if err then
      return nil, "could not load plugins: " .. err
    end

    if plugin.enabled and plugin.name == plugin_name then
      local err = get_snis_for_plugin(db, plugin, snis, options)
      if err then
        return nil, err
      end

      if snis["*"] then
        break
      end
    end
  end

  return snis
end


return _M
