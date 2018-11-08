local endpoints = require "kong.api.endpoints"
local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"


local unescape_uri = ngx.unescape_uri
local escape_uri = ngx.escape_uri
local null = ngx.null
local fmt = string.format


local function select_upstream(db, upstream_id, opts)
  local id = unescape_uri(upstream_id)
  if utils.is_valid_uuid(id) then
    return db.upstreams:select({ id = id }, opts)
  end

  return db.upstreams:select_by_name(id, opts)
end


local function select_target(db, upstream, target_id, opts)
  local id = unescape_uri(target_id)
  local filter = utils.is_valid_uuid(id) and { id = id } or { target = id }

  return db.targets:select_by_upstream_filter({ id = upstream.id }, filter, opts)
end


local function post_health(self, db, is_healthy)
  local args = self.args.post
  local opts = endpoints.extract_options(args, db.upstreams.schema, "select")

  local upstream, _, err_t = select_upstream(db, self.params.upstreams, opts)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not upstream then
    return responses.send_HTTP_NOT_FOUND()
  end

  opts = endpoints.extract_options(args, db.targets.schema, "select", opts)

  local target, _, err_t = select_target(db, upstream, self.params.targets, opts)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if target then
    local ok, err = db.targets:post_health(upstream, target, is_healthy)
    if not ok then
      responses.send_HTTP_BAD_REQUEST(err)
    end
  end

  return responses.send_HTTP_NO_CONTENT()
end


return {
  ["/upstreams/:upstreams/health"] = {
    GET = function(self, db)
      local args = self.args.uri
      local opts = endpoints.extract_options(args, db.upstreams.schema, "select")

      local upstream, _, err_t = select_upstream(db, self.params.upstreams, opts)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not upstream then
        return responses.send_HTTP_NOT_FOUND()
      end

      local upstream_pk = { id = upstream.id }
      local size, err = endpoints.get_page_size(args)
      if err then
        return endpoints.handle_error(db.targets.errors:invalid_size(err))
      end

      opts = endpoints.extract_options(args, db.targets.schema, "select")

      local targets_with_health, _, err_t, offset =
        db.targets:page_for_upstream_with_health(upstream_pk, size, args.offset, opts)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      local next_page = offset and fmt("/upstreams/%s/health?offset=%s",
                                       escape_uri(upstream.id),
                                       escape_uri(offset)) or null

      local node_id, err = kong.node.get_id()
      if err then
        ngx.log(ngx.ERR, "failed getting node id: ", err)
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
      local args = self.args.uri
      local opts = endpoints.extract_options(args, db.upstreams.schema, "select")

      local upstream, _, err_t = select_upstream(db, self.params.upstreams, opts)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not upstream then
        return responses.send_HTTP_NOT_FOUND()
      end

      local upstream_pk = { id = upstream.id }
      local opts = endpoints.extract_options(args, db.targets.schema, "select")
      local size, err = endpoints.get_page_size(args)
      if err then
        return endpoints.handle_error(db.targets.errors:invalid_size(err))
      end

      local targets, _, err_t, offset = db.targets:page_for_upstream_raw(upstream_pk,
                                                                         size,
                                                                         args.offset,
                                                                         opts)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      local next_page = offset and fmt("/upstreams/%s/targets/all?offset=%s",
                                       escape_uri(upstream.id),
                                       escape_uri(offset)) or null

      return responses.send_HTTP_OK({
        data   = targets,
        offset = offset,
        next   = next_page,
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
      local args = self.args.uri
      local opts = endpoints.extract_options(args, db.upstreams.schema, "select")

      local upstream, _, err_t = select_upstream(db, self.params.upstreams, opts)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not upstream then
        return responses.send_HTTP_NOT_FOUND()
      end

      opts = endpoints.extract_options(args, db.targets.schema, "select")

      local target, _, err_t = select_target(db, upstream, self.params.targets, opts)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if target then
        opts = endpoints.extract_options(args, db.targets.schema, "delete")

        local _, _, err_t = db.targets:delete({ id = target.id }, opts)
        if err_t then
          return endpoints.handle_error(err_t)
        end
      end

      return responses.send_HTTP_NO_CONTENT()
    end
  },
}

