local insert = table.insert


local _M = {}


local function visit(current, neighbors_map, visited, marked, sorted)
  if visited[current] then
    return true
  end

  if marked[current] then
    return nil, "Cycle detected, cannot sort topologically"
  end

  marked[current] = true

  local schemas_pointing_to_current = neighbors_map[current]
  if schemas_pointing_to_current then
    local neighbor, ok, err
    for i = 1, #schemas_pointing_to_current do
      neighbor = schemas_pointing_to_current[i]
      ok, err = visit(neighbor, neighbors_map, visited, marked, sorted)
      if not ok then
        return nil, err
      end
    end
  end

  marked[current] = false

  visited[current] = true

  insert(sorted, 1, current)

  return true
end


function _M.topological_sort(items, get_neighbors)
  local neighbors_map = {}
  local source, destination
  local neighbors
  for i = 1, #items do
    source = items[i] -- services
    neighbors = get_neighbors(source)
    for j = 1, #neighbors do
      destination = neighbors[j] --routes
      neighbors_map[destination] = neighbors_map[destination] or {}
      insert(neighbors_map[destination], source)
    end
  end

  local sorted = {}
  local visited = {}
  local marked = {}

  local current, ok, err
  for i = 1, #items do
    current = items[i]
    if not visited[current] and not marked[current] then
      ok, err = visit(current, neighbors_map, visited, marked, sorted)
      if not ok then
        return nil, err
      end
    end
  end

  return sorted
end


return _M
