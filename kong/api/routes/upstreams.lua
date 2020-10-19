local endpoints = require "kong.api.endpoints"
local utils = require "kong.tools.utils"


local kong = kong
local escape_uri = ngx.escape_uri
local unescape_uri = ngx.unescape_uri
local null = ngx.null
local tostring = tostring
local fmt = string.format


local function post_health(self, db, is_healthy)
  local upstream, _, err_t = endpoints.select_entity(self, db, db.upstreams.schema)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not upstream then
    return kong.response.exit(404, { message = "Not found" })
  end

  local target
  if utils.is_valid_uuid(unescape_uri(self.params.targets)) then
    target, _, err_t = endpoints.select_entity(self, db, db.targets.schema)

  else
    local opts = endpoints.extract_options(self.args.uri, db.targets.schema, "select")
    local upstream_pk = db.upstreams.schema:extract_pk_values(upstream)
    local filter = { target = unescape_uri(self.params.targets) }
    target, _, err_t = db.targets:select_by_upstream_filter(upstream_pk, filter, opts)
  end

  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not target or target.upstream.id ~= upstream.id then
    return kong.response.exit(404, { message = "Not found" })
  end

  local ok, err = db.targets:post_health(upstream, target, self.params.address, is_healthy)
  if not ok then
    return kong.response.exit(400, { message = err })
  end

  return kong.response.exit(204)
end


local function select_target_cb(self, db, upstream, target)
  if target and target.weight ~= 0 then
    return kong.response.exit(200, target)
  end

  return kong.response.exit(404, { message = "Not found" })
end


local function update_target_cb(self, db, upstream, target)
  self.params.targets = db.targets.schema:extract_pk_values(target)
  local entity, _, err_t = endpoints.update_entity(self, db, db.targets.schema)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  return kong.response.exit(200, entity)
end


local function delete_target_cb(self, db, upstream, target)
  self.params.targets = db.targets.schema:extract_pk_values(target)
  local _, _, err_t = endpoints.delete_entity(self, db, db.targets.schema)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  return kong.response.exit(204) -- no content
end


local function target_endpoint(self, db, callback)
  local upstream, _, err_t = endpoints.select_entity(self, db, db.upstreams.schema)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not upstream then
    return kong.response.exit(404, { message = "Not found" })
  end

  local target
  if utils.is_valid_uuid(unescape_uri(self.params.targets)) then
    target, _, err_t = endpoints.select_entity(self, db, db.targets.schema)

  else
    local opts = endpoints.extract_options(self.args.uri, db.targets.schema, "select")
    local upstream_pk = db.upstreams.schema:extract_pk_values(upstream)
    local filter = { target = unescape_uri(self.params.targets) }
    target, _, err_t = db.targets:select_by_upstream_filter(upstream_pk, filter, opts)
  end

  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not target or target.upstream.id ~= upstream.id then
    return kong.response.exit(404, { message = "Not found" })
  end

  return callback(self, db, upstream, target)
end


local function update_existent_target(self, db)
  local upstream = endpoints.select_entity(self, db, db.upstreams.schema)
  local filter = { target = unescape_uri(self.params.target) }
  local opts = endpoints.extract_options(self.args.uri, db.targets.schema, "select")
  local target = db.targets:select_by_upstream_filter(upstream, filter, opts)

  if target then
    self.params.targets = db.targets.schema:extract_pk_values(target)
    return endpoints.update_entity(self, db, db.targets.schema)
  end

  return nil
end


return {
  ["/upstreams/:upstreams/health"] = {
    GET = function(self, db)
      local upstream, _, err_t = endpoints.select_entity(self, db, db.upstreams.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not upstream then
        return kong.response.exit(404, { message = "Not found" })
      end

      local node_id, err = kong.node.get_id()
      if err then
        kong.log.err("failed to get node id: ", err)
      end

      if tostring(self.params.balancer_health) == "1" then
        local upstream_pk = db.upstreams.schema:extract_pk_values(upstream)
        local balancer_health  = db.targets:get_balancer_health(upstream_pk)
        return kong.response.exit(200, {
          data = balancer_health,
          next = null,
          node_id = node_id,
        })
      end

      self.params.targets = db.upstreams.schema:extract_pk_values(upstream)
      local targets_with_health, _, err_t, offset =
        endpoints.page_collection(self, db, db.targets.schema, "page_for_upstream_with_health")

      if err_t then
        return endpoints.handle_error(err_t)
      end

      local next_page = offset and fmt("/upstreams/%s/health?offset=%s",
                                       self.params.upstreams,
                                       escape_uri(offset)) or null

      return kong.response.exit(200, {
        data    = targets_with_health,
        offset  = offset,
        next    = next_page,
        node_id = node_id,
      })
    end
  },

  ["/upstreams/:upstreams/targets"] = {
    GET = endpoints.get_collection_endpoint(kong.db.targets.schema,
                                            kong.db.upstreams.schema,
                                            "upstream",
                                            "page_for_upstream"),
    POST = function(self, db)
      -- updating a target using POST is a compatibility with existent API and
      -- should be deprecated in next major version
      local entity, _, err_t = update_existent_target(self, db)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if entity then
        return kong.response.exit(200, entity, { ["Deprecation"] = "true" })
      end

      local create = endpoints.post_collection_endpoint(kong.db.targets.schema,
                        kong.db.upstreams.schema, "upstream")
      return create(self, db)
    end
  },

  ["/upstreams/:upstreams/targets/all"] = {
    GET = endpoints.get_collection_endpoint(kong.db.targets.schema,
                                            kong.db.upstreams.schema,
                                            "upstream",
                                            "page_for_upstream_raw")
  },

  ["/upstreams/:upstreams/targets/:targets/healthy"] = {
    POST = function(self, db)
      return post_health(self, db, true)
    end,
  },

  ["/upstreams/:upstreams/targets/:targets/unhealthy"] = {
    POST = function(self, db)
      return post_health(self, db, false)
    end,
  },

  ["/upstreams/:upstreams/targets/:targets/:address/healthy"] = {
    POST = function(self, db)
      return post_health(self, db, true)
    end,
  },

  ["/upstreams/:upstreams/targets/:targets/:address/unhealthy"] = {
    POST = function(self, db)
      return post_health(self, db, false)
    end,
  },

  ["/upstreams/:upstreams/targets/:targets"] = {
    DELETE = function(self, db)
      return target_endpoint(self, db, delete_target_cb)
    end,
    GET = function(self, db)
      return target_endpoint(self, db, select_target_cb)
    end,
    PATCH = function(self, db)
      return target_endpoint(self, db, update_target_cb)
    end,
    PUT = function(self, db)
      return target_endpoint(self, db, update_target_cb)
    end,
  },
}

