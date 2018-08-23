local endpoints   = require "kong.api.endpoints"
local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"
local public = require "kong.tools.public"


local function select_upstream(db, upstream_id)
  local id = ngx.unescape_uri(upstream_id)
  if utils.is_valid_uuid(id) then
    return db.upstreams:select({ id = id })
  end
  return db.upstreams:select_by_name(id)
end


local function select_target(db, upstream, target_id)
  local id = ngx.unescape_uri(target_id)
  local filter = utils.is_valid_uuid(id) and { id = id } or { target = id }
  return db.targets:select_by_upstream_filter({ id = upstream.id }, filter)
end


local function post_health(self, db, is_healthy)
  local upstream, _, err_t = select_upstream(db, self.params.upstreams)
  if err_t then
    return endpoints.handle_error(err_t)
  end
  local target, _, err_t = select_target(db, upstream, self.params.targets)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  local ok, err = db.targets:post_health(upstream, target, is_healthy)
  if not ok then
    responses.send_HTTP_BAD_REQUEST(err)
  end

  return responses.send_HTTP_NO_CONTENT()
end


return {
  ["/upstreams/:upstreams/health"] = {
    GET = function(self, db)
      local node_id, err = public.get_node_id()
      if err then
        ngx.log(ngx.ERR, "failed getting node id: ", err)
      end

      local upstream, _, err_t = select_upstream(db, self.params.upstreams)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      local targets_with_health, _, err_t, offset =
      db.targets:page_for_upstream_with_health({ id = upstream.id },
                                               tonumber(self.args.size),
                                               self.args.offset)
      if not targets_with_health then
        return endpoints.handle_error(err_t)
      end

      local next_page = ngx.null
      if offset then
        next_page = string.format("/upstreams/%s/health?offset=%s",
                                  ngx.escape_uri(upstream.id),
                                  ngx.escape_uri(offset))

      end

      return responses.send_HTTP_OK({
        data    = targets_with_health,
        offset  = offset,
        next    = next_page,
        node_id = node_id,
      })
    end
  },

  ["/upstreams/:upstreams/targets/all"] = {
    GET = function(self, db)
      local upstream, _, err_t = select_upstream(db, self.params.upstreams)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      local targets, _, err_t, offset =
        db.targets:page_for_upstream_raw({ id = upstream.id },
                                         tonumber(self.args.size),
                                         self.args.offset)
      if not targets then
        return endpoints.handle_error(err_t)
      end

      local next_page
      if offset then
        next_page = string.format("/upstreams/%s/targets/all?offset=%s",
                                  ngx.escape_uri(upstream.id),
                                  ngx.escape_uri(offset))
      end


      return responses.send_HTTP_OK({
        data  = targets,
        offset  = offset,
        next    = next_page,
      })
    end
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
      local upstream, _, err_t = select_upstream(db, self.params.upstreams)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      local target, _, err_t = select_target(db, upstream, self.params.targets)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      local _, _, err_t = db.targets:delete({ id = target.id })
      if err_t then
        return endpoints.handle_error(err_t)
      end
      return responses.send_HTTP_NO_CONTENT()
    end
  }
}

