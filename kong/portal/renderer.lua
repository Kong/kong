local pl_tablex   = require "pl.tablex"
local pl_stringx   = require "pl.stringx"
local constants    = require "kong.constants"
local singletons   = require "kong.singletons"
local ws_helper    = require "kong.workspaces.helper"
local ws_constants = constants.WORKSPACE_CONFIG


local function find_next_partial(page)
  local partial_match = string.match(page, '{{>.-}}')

  if not partial_match then
    partial_match = string.match(page, '{{#>.-}}')
  end

  return partial_match
end


local function parse_partial_name(partial)
  local _, name, _ = string.match(partial, '({{>)%s*(.*)%s*(}})')

  if not name then
    _, name, _ = string.match(partial, '({{#>)%s*(.*)%s*(}})')
  end

  local split_name = pl_stringx.split(name, ' ')[1]

  return split_name
end


local function replace_partial_in_page(page, partial, match)
  return pl_stringx.replace(page, match, partial)
end


local function get_next_route (path, extension)
  local split_path = pl_stringx.split(path, '/')

  if extension ~= '' then
    extension = split_path[#split_path] .. '/' .. extension
  else
    extension = split_path[#split_path]
  end
  table.remove(split_path)
  path = pl_stringx.join('/', split_path)

  return path, extension
end


local function find_file (filename, filetype, is_authenticated)
  if not is_authenticated and not pl_stringx.startswith(filename, "unauthenticated/") then
    filename = 'unauthenticated/' .. filename
  end

  return singletons.dao.files:find_all({
    name = filename,
    type = filetype,
    auth = is_authenticated,
  })
end


local function find_partial_by_name (partial_name, is_authenticated)
  return singletons.dao.files:find_all({
    name = partial_name,
    type = 'partial',
    auth = is_authenticated
  })
end


local function search_for_page (path, is_authenticated)
  local page = find_file(path, 'page', is_authenticated)

  if not next(page) then
    page = find_file(path .. '/index', 'page', is_authenticated)
  end

  return page
end


local function set_page_if_blacklist_match(path, page)
  local blacklist = { "login", "register", "dashboard", "settings" }

  if pl_tablex.find(blacklist, path) then
    return page
  end

  return {}
end


local function search_for_valid_spec (path, extension, is_authenticated)
  local path, extension = get_next_route(path, extension)
  local spec = {}

  if (is_authenticated) then
    spec = find_file(extension, 'spec', true)
  end

  if not next(spec) then
    spec = find_file(extension, 'spec', false)
  end

  local spec_loader = {}

  if next(spec) then
    spec_loader = find_file(path .. '/loader', 'page', true)
  end

  local pathname

  if next(spec) and not next(spec_loader) then
    if path == '' then
      pathname = 'loader'
    else
      pathname = path .. '/loader'
    end

    if not next(spec_loader) and is_authenticated then
      spec_loader = find_file(pathname, 'page', true)
    end

    if not next(spec_loader) then
      spec_loader = find_file(pathname, 'page', false)
    end
  end

  if not next(spec_loader) and path ~= '' then
    return search_for_valid_spec(path, extension, is_authenticated)
  end

  return spec_loader, spec
end


local function find_partials_in_page (page, partials, is_authenticated)
  local partial_match = find_next_partial(page)

  if not partial_match then
    return partials
  end

  local partial = {}
  local partial_name = parse_partial_name(partial_match)

  if is_authenticated then
    partial = find_partial_by_name(partial_name, true)
  end

  if not next(partial) then
    partial = find_partial_by_name(partial_name, false)
  end

  if not next(partial) or partials[partial_name] then
    partial = { contents = '' }
    page = replace_partial_in_page(page, partial.contents, partial_match)
    return find_partials_in_page(page, partials, is_authenticated)
  end

  partials[partial_name] = partial[1]
  page = replace_partial_in_page(page, partial[1].contents, partial_match)
  return find_partials_in_page(page, partials, is_authenticated)
end


local function retrieve_partials (self, page)
  local partials = {}
  local page = page.contents
  local is_authenticated = self.is_authenticated

  return find_partials_in_page(page, partials, is_authenticated)
end


local function retrieve_page_and_spec (self)
  local is_authenticated = self.is_authenticated
  local workspace = ws_helper.get_workspace()
  local portal_auth = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH,
                                                                    workspace)

  local path = self.path
  local page = {}
  local spec = {}

  local login = find_file('login', 'page', false)
  local not_found = find_file('404', 'page', false)

  path = pl_stringx.replace(path, '/' .. workspace.name .. '/', '')
  path = pl_stringx.replace(path, '/' .. workspace.name, '')
  path = pl_stringx.rstrip(path, '/')
  path = pl_stringx.lstrip(path, '/')

  if path == '' or path == '/' then
    path = 'index'
  end

  if portal_auth == nil or portal_auth == '' then
    page = set_page_if_blacklist_match(path, not_found)
  end

  -- if authenticated, search for valid authenticated page
  if not next(page) and is_authenticated then
    page = search_for_page(path, true)
  end

  -- search for valid page under unauthenticated namespace
  if not next(page) then
    page = search_for_page(path, false)
  end

  if not next(page) then
    page, spec = search_for_valid_spec(path, '', is_authenticated)
  end

  -- if page is not found and user is not authenticated, prompt for login
  if not next(page) and not is_authenticated  then
    page = login
  end

  -- default to 404 if no page is found
  if not next(page) then
    page = not_found
  end

  return page[1], spec[1]
end


local function compile_assets(self)
  local page, spec = retrieve_page_and_spec(self)
  local partials_dict = retrieve_partials(self, page)
  local partials = {}

  for idx, partial in pairs(partials_dict) do
    table.insert(partials, partial)
  end

  return page, partials, spec
end


return {
  compile_assets = compile_assets,
  -- only exposed for unit testing
  retrieve_page_and_spec = retrieve_page_and_spec,
  retrieve_partials = retrieve_partials,
  find_partials_in_page = find_partials_in_page,
  replace_partial_in_page = replace_partial_in_page,
  search_for_valid_spec = search_for_valid_spec,
  find_partial_by_name = find_partial_by_name,
  search_for_page = search_for_page,
  get_next_route = get_next_route,
  parse_partial_name = parse_partial_name,
  find_next_partial = find_next_partial,
}
