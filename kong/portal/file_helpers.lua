local pl_stringx = require "pl.stringx"


local decode_base64 = ngx.decode_base64
local split  = pl_stringx.split
local match  = string.match
local gsub   = string.gsub


local content_extension_list = {
  "txt", "md", "html", "json", "yaml", "yml",
}

local content_extension_err = "invalid content extension, must be one of:" .. table.concat(content_extension_list, ", ")


local function to_bool(res)
  return not not res
end

local function get_ext(path)
  return match(path, "%.(%w+)$")
end


local function is_html_ext(path)
  return get_ext(path) == "html"
end


local function is_valid_content_ext(path)
  local ext = get_ext(path)
  for _, v in ipairs(content_extension_list) do
    if ext == v then
      return true
    end
  end

  return false, content_extension_err
end


local function get_prefix(path)
  return match(path, "^(%w+)/")
end


local function is_content_path(path)
  return get_prefix(path) == "content"
end


local function is_layout_path(path)
  return to_bool(match(path, "^themes/%w+/layouts/"))
end


local function is_partial_path(path)
  return to_bool(match(path, "^themes/%w+/partials/"))
end


local function is_asset_path(path)
  return to_bool(match(path, "^themes/%w+/assets/"))
end


local function is_content(file)
  return is_content_path(file.path) and is_valid_content_ext(file.path)
end


local function is_layout(file)
  return is_layout_path(file.path) and is_html_ext(file.path)
end


local function is_partial(file)
  return is_partial_path(file.path) and is_html_ext(file.path)
end


local function is_asset(file)
  return is_asset_path(file.path)
end


local function decode_file(file)
  local contents = file.contents
  local split_content = split(file.contents, ";")

  if next(split_content) and split(split_content[1], ":")[1] == "data" then
    contents = split(split_content[2], ",")[2]
  end

  contents = gsub(contents, "\n", "")

  local decoded_contents = decode_base64(contents)
  if decoded_contents then
    file.contents = decoded_contents
  end

  return file
end


return {
  is_content  = is_content,
  is_content_path = is_content_path,
  is_valid_content_ext = is_valid_content_ext,
  is_layout   = is_layout,
  is_layout_path = is_layout_path,
  is_partial  = is_partial,
  is_partial_path = is_partial_path,
  is_asset    = is_asset,
  is_asset_path = is_asset_path,
  is_html_ext = is_html_ext,
  get_prefix = get_prefix,
  get_ext = get_ext,
  decode_file = decode_file,
  content_extension_list = content_extension_list,

}

