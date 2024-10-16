local buffer = require "string.buffer"
local wasm = require "kong.runloop.wasm"
local wasmx_shm


local fmt = string.format
local str_find = string.find
local str_match = string.match
local str_sub = string.sub
local table_insert = table.insert
local table_sort = table.sort
local buf_new = buffer.new
local ngx_say = ngx.say


local _M = {}


local FLUSH_EVERY = 100


local function sorted_iter(ctx)
  local v = ctx.t[ctx.sorted_keys[ctx.i]]
  ctx.i = ctx.i + 1

  return v
end


local function sorted_pairs(t)
  local sorted_keys = {}

  for k, _ in pairs(t) do
    table_insert(sorted_keys, k)
  end

  table_sort(sorted_keys)

  return sorted_iter, { t = t, sorted_keys = sorted_keys, i = 1 }
end


local function parse_pw_key(key)
  local name = key
  local labels = {}
  local header_size = 3  -- pw.
  local first_label = #key

  local second_dot_pos, _ = str_find(key, "%.", header_size + 1)
  local filter_name = str_sub(key, header_size + 1, second_dot_pos - 1)

  local filter_config = wasm.filters_by_name[filter_name].config or {}
  local patterns = filter_config.pw_metrics
                   and filter_config.pw_metrics.label_patterns or {}

  for _, pair in ipairs(patterns) do
    local label_kv, label_v = str_match(key, pair.pattern)
    if label_kv then
      local label_k = str_sub(label_kv, 0, str_find(label_kv, "="))
      local label_k_start, _ = str_find(key, label_k)

      first_label = (label_k_start < first_label) and label_k_start or first_label

      table_insert(labels, { pair.label, label_v })
    end
  end

  if first_label ~= #key then
    name = str_sub(key, 0, first_label - 1)
  end

  return name, labels
end


local function parse_key(key)
  -- TODO: parse wa. (WasmX metrics) and lua. (metrics defined in Lua land)
  local header = { pw = "pw." }

  local name = key
  local labels = {}

  local is_pw = #key > #header.pw and key:sub(0, #header.pw) == header.pw

  if is_pw then
    name, labels = parse_pw_key(key)
  end

  name = name:gsub("%.", "_")

  return name, labels
end


local function serialize_labels(labels)
  local buf = buf_new()

  for _, pair in ipairs(labels) do
    buf:put(fmt(',%s="%s"', pair[1], pair[2]))
  end

  buf:get(1)  -- discard trailing comma

  return "{" .. buf:get() .. "}"
end


local function serialize_metric(m, buf)
  buf:put(fmt("# HELP %s\n# TYPE %s %s", m.name, m.name, m.type))

  if m.type == "histogram" then
    local sum_lines_buf = buf_new()
    local count_lines_buf = buf_new()

    for _, pair in ipairs(m.labels) do
      local count, sum = 0, 0
      local labels, labeled_m = pair[1], pair[2]
      local slabels = (#labels > 0) and serialize_labels(labels) or ""

      local blabels = (#labels > 0) and (slabels:sub(1, #slabels - 1) .. ",") or "{"

      for _, bin in ipairs(labeled_m.value) do
        local ub = (bin.ub ~= 4294967295) and bin.ub or "+Inf"
        local ubl = fmt('le="%s"', ub)

        count = count + bin.count

        buf:put(fmt("\n%s%s %s", m.name, blabels .. ubl .. "}", count))
      end

      sum = sum + labeled_m.sum

      sum_lines_buf:put(fmt("\n%s_sum%s %s", m.name, slabels, sum))
      count_lines_buf:put(fmt("\n%s_count%s %s", m.name, slabels, count))
    end

    buf:put(sum_lines_buf:get())
    buf:put(count_lines_buf:get())

  else
    for _, pair in ipairs(m.labels) do
      local labels, labeled_m = pair[1], pair[2]
      local slabels = (#labels > 0) and serialize_labels(labels) or ""

      buf:put(fmt("\n%s%s %s", m.name, slabels, labeled_m.value))
    end
  end

  buf:put("\n")
end


_M.metric_data = function()
  local i = 0
  local metrics = {}
  local parsed = {}
  local buf = buf_new()

  -- delayed require of the WasmX module, to ensure it is loaded
  -- after ngx_wasm_module.so is loaded.
  if not wasmx_shm then
    local ok, _wasmx_shm = pcall(require, "resty.wasmx.shm")
    if ok then
      wasmx_shm = _wasmx_shm
    end
  end

  if not wasmx_shm then
    return
  end

  wasmx_shm.metrics:lock()

  for key in wasmx_shm.metrics:iterate_keys() do
    table_insert(metrics, { key, wasmx_shm.metrics:get_by_name(key, { prefix = false })})
  end

  wasmx_shm.metrics:unlock()

  -- in WasmX the different labels of a metric are stored as separate metrics;
  -- aggregate those separate metrics into a single one.
  for _, pair in ipairs(metrics) do
    local key = pair[1]
    local m = pair[2]
    local name, labels = parse_key(key)

    parsed[name] = parsed[name] or { name = name, type = m.type, labels = {} }

    table_insert(parsed[name].labels, { labels, m })
  end

  for metric_by_label in sorted_pairs(parsed) do
    buf:put(serialize_metric(metric_by_label, buf))

    i = i + 1

    if i % FLUSH_EVERY == 0 then
      ngx_say(buf:get())
    end
  end

  ngx_say(buf:get())
end


return _M
