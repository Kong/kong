
local protobuf = {}

do
  local structpb_value, structpb_list, structpb_struct

  function structpb_value(v)
    local t = type(v)

    local bool_v = nil
    if t == "boolean" then
      bool_v = v
    end

    local list_v = nil
    local struct_v = nil

    if t == "table" then
      if t[1] ~= nil then
        list_v = structpb_list(v)
      else
        struct_v = structpb_struct(v)
      end
    end

    return {
      null_value = t == "nil" and 1 or nil,
      bool_value = bool_v,
      number_value = t == "number" and v or nil,
      string_value = t == "string" and v or nil,
      list_value = list_v,
      struct_value = struct_v,
    }
  end

  function structpb_list(l)
    local out = {}
    for i, v in ipairs(l) do
      out[i] = structpb_value(v)
    end
    return { values = out }
  end

  function structpb_struct(d)
    local out = {}
    for k, v in pairs(d) do
      out[k] = structpb_value(v)
    end
    return { fields = out }
  end

  protobuf.pbwrap_struct = structpb_struct
end

do
  local structpb_value, structpb_list, structpb_struct

  function structpb_value(v)
    if type(v) ~= "table" then
      return v
    end

    if v.list_value then
      return structpb_list(v.list_value)
    end

    if v.struct_value then
      return structpb_struct(v.struct_value)
    end

    return v.bool_value or v.string_value or v.number_value or v.null_value
  end

  function structpb_list(l)
    local out = {}
    if type(l) == "table" then
      for i, v in ipairs(l.values or l) do
        out[i] = structpb_value(v)
      end
    end
    return out
  end

  function structpb_struct(struct)
    if type(struct) ~= "table" then
      return struct
    end

    local out = {}
    for k, v in pairs(struct.fields or struct) do
      out[k] = structpb_value(v)
    end
    return out
  end

  protobuf.pbunwrap_struct = structpb_struct
end


return protobuf
