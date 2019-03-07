local blueprints = require "spec.fixtures.blueprints"
local tablex = require "pl.tablex"


local dc_blueprints = {}


local null = ngx.null


local function reset()
  return {
    _format_version = "1.1"
  }
end


local function remove_nulls(tbl)
  for k,v in pairs(tbl) do
    if v == null then
      tbl[k] = nil
    elseif type(v) == "table" then
      tbl[k] = remove_nulls(v)
    end
  end
  return tbl
end


function dc_blueprints.new(db)
  local dc_as_db = {}

  local save_dc
  local dc = reset()

  for name, _ in pairs(db.daos) do
    dc_as_db[name] = {
      insert = function(_, tbl)
        tbl = tablex.deepcopy(tbl)
        if not dc[name] then
          dc[name] = {}
        end
        local schema = db.daos[name].schema
        tbl = schema:process_auto_fields(tbl, "insert")
        for fname, field in schema:each_field() do
          if field.type == "foreign" then
            tbl[fname] = type(tbl[fname]) == "table"
                         and tbl[fname].id
                         or nil
          end
        end
        table.insert(dc[name], remove_nulls(tbl))
        return tablex.deepcopy(tbl)
      end,
      update = function(_, id, tbl)
        if not dc[name] then
          return nil, "not found"
        end
        tbl = tablex.deepcopy(tbl)
        local element
        for _, e in ipairs(dc[name]) do
          if e.id == id then
            element = e
            break
          end
        end
        if not element then
          return nil, "not found"
        end
        for k,v in pairs(tbl) do
          element[k] = v
        end
        return element
      end
    }
  end

  local bp = blueprints.new(dc_as_db)

  bp.done = function()
    local ret = dc
    save_dc = dc
    dc = reset()
    return ret
  end

  bp.reset_back = function()
    dc = save_dc
  end

  return bp
end


return dc_blueprints
