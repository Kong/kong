local parser = {}


local function starts_with(str, start)
   return str and str:sub(1, #start) == start
end


local function trim(str)
   return str and (str:gsub("^%s*(.-)%s*$", "%1"))
end


-- Remove the initial #, and the space after it, if it exists
-- (does not remove two or more spaces)
local function remove_hash_prefix(str)
  local hash_prefix = str:match("^%s*#")
  if hash_prefix then
    str = str:sub(#hash_prefix + 1, #str)
  end
  if str:sub(1, 1) == " " and str:sub(2, 2) ~= " " then
    str = str:sub(2, #str)
  end
  return str
end


local function cleanup(str)
  if not str then return nil end
  return trim(remove_hash_prefix(str))
end


-- Parses a description into an array of blocks. It recognizes 3 types:
--
-- A regular markdown paragraph looks like this:
--   { type = "p", text = "A regular paragrap looks like this:" }
--
-- A ul paragraph with two items like:
-- * First item
-- * Second item
-- Looks like this:
--   { type = "ul", items = { "First item", "Second item" } }
--
-- A code section with code like:
-- ```
-- print("hello")
-- ```
-- Looks lie:
--   { type = "code", text = 'print("hello")' }
--
-- @param array of lines containing a description
-- @returns an array of blocks.
local function parse_description(description_buffer)
  local blocks = {}
  local block = { type = "p" }
  local buffer = {}

  local finish_block = function()
    if #buffer > 0 then
      if block.type == "p" or block.type == "code" then
        block.text = table.concat(buffer, "\n")
      else
        block.items[#block.items + 1] = table.concat(buffer, " ")
      end
      buffer = {}
      blocks[#blocks + 1] = block
    end
  end


  local new_block = function(new_type)
    finish_block()
    block = { type = new_type }
    if new_type == "ul" then
      block.items = {}
    end
  end

  for _, line in ipairs(description_buffer) do
    if block.type == "ul" then
      if line:sub(1, 2) == "- " then
        block.items[#block.items + 1] = table.concat(buffer, " ")
        buffer = { (line:sub(3, #line)) }

      elseif line:sub(1, 2) == "  " then
        buffer[#buffer + 1] = line:sub(2, #line)

      else -- ul finished
        if line:sub(-1) == "." then
          buffer[#buffer + 1] = line
          new_block("p")

        elseif #line == 0 then
          new_block("p")

        else
          new_block("p")
          buffer[#buffer + 1] = line
        end
      end

    else -- not ul
      -- ul starting
      if line:sub(1, 2) == "- " then
        new_block("ul")
        buffer[1] = line:sub(3, #line)

      -- code starting
      elseif line:sub(1, 3) == "```" then
        if block.is_code then
          new_block("p")

        else
          new_block("code")
        end
      else
        if line:sub(-1) == "." then
          buffer[#buffer + 1] = line
          new_block("p")

        elseif #line == 0 then
          new_block("p")

        else
          buffer[#buffer + 1] = line
        end
      end
    end
  end

  finish_block()

  return blocks
end


function parser.parse(lines)

  local current_line_index = 0
  local current_line = ""
  -- next line. Skips empty lines automatically
  -- Does not skip lines with just the # sign
  local nl = function()
    repeat
      current_line_index = current_line_index + 1
      current_line = lines[current_line_index]
    until not current_line or #current_line > 0
  end

  local res = {}
  local current_section
  local current_var
  local description_buffer

  local finish_current_var = function()
    if not current_var then return end

    if description_buffer then
      current_var.description = parse_description(description_buffer)
      description_buffer = nil
    end

    current_var = nil
  end

  local add_description_line = function(line)
    if not line then
      return
    end
    description_buffer[#description_buffer + 1] = remove_hash_prefix(line)
  end

  repeat
    nl()
    if starts_with(current_line, "#----") then
      finish_current_var()
      nl()
      local current_section_name = cleanup(current_line)
      if current_section_name then
        current_section = { name = current_section_name, vars = {} }
        description_buffer = {}
        table.insert(res, current_section)
        nl() -- skip the #----- after the section name
      end

    elseif current_section and current_line then
      local var_name, default, first_description_line = string.match(current_line, "#([^%s]+) = ([^#]*)#?%s*(.*)")
      if var_name then
        if current_section and not current_var then
          current_section.description = parse_description(description_buffer)
        end

        finish_current_var()

        default = cleanup(default)
        if #default == 0 then
          default = nil
        end

        current_var = {
          name = var_name,
          default = default,
        }
        table.insert(current_section.vars, current_var)
        description_buffer = {}
        add_description_line(first_description_line)

      -- skip the intial intro text with if current_section then ...
      -- if we are not parsing a new section header or a new var (with an assignment),
      -- just keep adding lines to the current description
      elseif current_section then
        add_description_line(current_line)
      end
    end
  until not current_line

  finish_current_var()

  return res
end


return parser
