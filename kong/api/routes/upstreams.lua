local endpoints = require "kong.api.endpoints"
local utils = require "kong.tools.utils"


local kong = kong
local escape_uri = ngx.escape_uri
local unescape_uri = ngx.unescape_uri
local null = ngx.null
local fmt = string.format


local function post_health(self, db, is_healthy)
  local upstream, _, err_t = endpoints.select_entity(self, db, db.upstreams.schema)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not upstream then
    return endpoints.not_found()
  end

  local target
  if utils.is_valid_uuid(unescape_uri(self.params.targets)) then
    target, _, err_t = endpoints.select_entity(self, db, db.targets.schema)

  else
    local opts = endpoints.extract_options(self.args.uri, db.targets.schema, "select")
    local upstream_pk = db.upstreams.schema:extract_pk_values(upstream)
    target, _, err_t = db.targets:select_by_upstream_target(upstream_pk, unescape_uri(self.params.targets), opts)
  end

  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not target then
    return endpoints.not_found()
  end

  local ok, err = db.targets:post_health(upstream, target, is_healthy)
  if not ok then
    return endpoints.bad_request(err)
  end

  return endpoints.no_content()
end


return {
  ["/upstreams/:upstreams/health"] = {
    GET = function(self, db)
      local upstream, _, err_t = endpoints.select_entity(self, db, db.upstreams.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not upstream then
        return endpoints.not_found()
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

      local node_id, err = kong.node.get_id()
      if err then
        kong.log.err("failed getting node id: ", err)
      end

      return endpoints.ok {
        data    = targets_with_health,
        offset  = offset,
        next    = next_page,
        node_id = node_id,
      }
    end
  },

  ["/upstreams/:upstreams/targets"] = {
    GET = endpoints.get_collection_endpoint(kong.db.targets.schema,
                                            kong.db.upstreams.schema,
                                            "upstream",
                                            "page_for_upstream_without_inactive"),
  },

  ["/upstreams/:upstreams/targets/all"] = {
    GET = endpoints.get_collection_endpoint(kong.db.targets.schema,
                                            kong.db.upstreams.schema,
                                            "upstream")
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

  ["/upstreams/:upstreams/targets/:targets"] = {
    DELETE = function(self, db)
      local upstream, _, err_t = endpoints.select_entity(self, db, db.upstreams.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not upstream then
        return endpoints.not_found()
      end

      local target
      if utils.is_valid_uuid(unescape_uri(self.params.targets)) then
        target, _, err_t = endpoints.select_entity(self, db, db.targets.schema)

      else
        local opts = endpoints.extract_options(self.args.uri, db.targets.schema, "select")
        local upstream_pk = db.upstreams.schema:extract_pk_values(upstream)
        target, _, err_t = db.targets:select_by_upstream_target(upstream_pk, unescape_uri(self.params.targets), opts)
      end

      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not target then
        return endpoints.not_found()
      end

      self.params.targets = db.upstreams.schema:extract_pk_values(target)
      _, _, err_t = endpoints.delete_entity(self, db, db.targets.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      return endpoints.no_content()
    end
  },
}

