local kong = kong

local foreign_entities = kong.db.foreign_entities

local function select_by_name(params)
  return params.dao:select_by_name(params.name)
end

local function get_cached(self, dao, cb)
  local name = self.params[dao.schema.name]

  local cache_key = dao:cache_key(name)
  local entity, err = kong.cache:get(cache_key, nil, cb, { dao = dao, name = name })

  if err then
    kong.log.debug(err)
  end

  if not entity then
    return kong.response.exit(404)
  end

  return kong.response.exit(200, entity)
end

return {
  ["/foreign_entities_cache_warmup/:foreign_entities"] = {
    schema = foreign_entities.schema,
    methods = {
      GET = function(self, db)
        return get_cached(self, foreign_entities, select_by_name)
      end,
    },
  },
}
