-- luacheck: ignore

----------------------------------------------------------------------
-- Utility functions
----------------------------------------------------------------------

local unpack = table.unpack or unpack

-- Returns the result of mapping the values in table t through the function f
local function map(t, f)
   local out = {}
   for k,v in pairs(t) do out[k] = f(v,k) end
   return out
end

-- Functional style if statement. (NOTE: no short circuit evaluation)
local function iff(t, a, b) if t then return a else return b end end

-- Splits the text into an array of separate lines.
local function split(text, sep)
   sep = sep or "\n"
   local lines = {}
   local pos = 1
   while true do
      local b,e = text:find(sep, pos)
      if not b then table.insert(lines, text:sub(pos)) break end
      table.insert(lines, text:sub(pos, b-1))
      pos = e + 1
   end
   return lines
end

-- Converts tabs to spaces
local function detab(text)
   local tab_width = 4
   local function rep(match)
      local spaces = -match:len()
      while spaces<1 do spaces = spaces + tab_width end
      return match .. string.rep(" ", spaces)
   end
   text = text:gsub("([^\n]-)\t", rep)
   return text
end

-- Applies string.find for every pattern in the list and returns the first match
local function find_first(s, patterns, index)
   local res = {}
   for _,p in ipairs(patterns) do
      local match = {s:find(p, index)}
      if #match>0 and (#res==0 or match[1] < res[1]) then res = match end
   end
   return unpack(res)
end

-- If a replacement array is specified, the range [start, stop] in the array is replaced
-- with the replacement array and the resulting array is returned. Without a replacement
-- array the section of the array between start and stop is returned.
local function splice(array, start, stop, replacement)
   if replacement then
      local n = stop - start + 1
      while n > 0 do
         table.remove(array, start)
         n = n - 1
      end
      for _,v in ipairs(replacement) do
         table.insert(array, start, v)
      end
      return array
   else
      local res = {}
      for i = start,stop do
         table.insert(res, array[i])
      end
      return res
   end
end

-- Outdents the text one step.
local function outdent(text)
   text = "\n" .. text
   text = text:gsub("\n  ? ? ?", "\n")
   text = text:sub(2)
   return text
end

-- Indents the text one step.
local function indent(text)
   text = text:gsub("\n", "\n    ")
   return text
end

-- Does a simple tokenization of html data. Returns the data as a list of tokens.
-- Each token is a table with a type field (which is either "tag" or "text") and
-- a text field (which contains the original token data).
local function tokenize_html(html)
   local tokens = {}
   local pos = 1
   while true do
      local start = find_first(html, {"<!%-%-", "<[a-z/!$]", "<%?"}, pos)
      if not start then
         table.insert(tokens, {type="text", text=html:sub(pos)})
         break
      end
      if start ~= pos then table.insert(tokens, {type="text", text = html:sub(pos, start-1)}) end

      local _, stop
      if html:match("^<!%-%-", start) then
         _,stop = html:find("%-%->", start)
      elseif html:match("^<%?", start) then
         _,stop = html:find("?>", start)
      else
         _,stop = html:find("%b<>", start)
      end
      if not stop then
         -- error("Could not match html tag " .. html:sub(start,start+30))
         table.insert(tokens, {type="text", text=html:sub(start, start)})
         pos = start + 1
      else
         table.insert(tokens, {type="tag", text=html:sub(start, stop)})
         pos = stop + 1
      end
   end
   return tokens
end

----------------------------------------------------------------------
-- Hash
----------------------------------------------------------------------

-- This is used to "hash" data into alphanumeric strings that are unique
-- in the document. (Note that this is not cryptographic hash, the hash
-- function is not one-way.) The hash procedure is used to protect parts
-- of the document from further processing.

local HASH = {
   -- Has the hash been inited.
   inited = false,

   -- The unique string prepended to all hash values. This is to ensure
   -- that hash values do not accidently coincide with an actual existing
   -- string in the document.
   identifier = "",

   -- Counter that counts up for each new hash instance.
   counter = 0,

   -- Hash table.
   table = {}
}

-- Inits hashing. Creates a hash_identifier that doesn't occur anywhere
-- in the text.
local function init_hash(text)
   HASH.inited = true
   HASH.identifier = ""
   HASH.counter = 0
   HASH.table = {}

   local s = "HASH"
   local counter = 0
   local id
   while true do
      id  = s .. counter
      if not text:find(id, 1, true) then break end
      counter = counter + 1
   end
   HASH.identifier = id
end

-- Returns the hashed value for s.
local function hash(s)
   assert(HASH.inited)
   if not HASH.table[s] then
      HASH.counter = HASH.counter + 1
      local id = HASH.identifier .. HASH.counter .. "X"
      HASH.table[s] = id
   end
   return HASH.table[s]
end

----------------------------------------------------------------------
-- Protection
----------------------------------------------------------------------

-- The protection module is used to "protect" parts of a document
-- so that they are not modified by subsequent processing steps.
-- Protected parts are saved in a table for later unprotection

-- Protection data
local PD = {
   -- Saved blocks that have been converted
   blocks = {},

   -- Block level tags that will be protected
   tags = {"p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote",
   "pre", "table", "dl", "ol", "ul", "script", "noscript", "form", "fieldset",
   "iframe", "math", "ins", "del"}
}

-- Pattern for matching a block tag that begins and ends in the leftmost
-- column and may contain indented subtags, i.e.
-- <div>
--    A nested block.
--    <div>
--        Nested data.
--     </div>
-- </div>
local function block_pattern(tag)
   return "\n<" .. tag .. ".-\n</" .. tag .. ">[ \t]*\n"
end

-- Pattern for matching a block tag that begins and ends with a newline
local function line_pattern(tag)
   return "\n<" .. tag .. ".-</" .. tag .. ">[ \t]*\n"
end

-- Protects the range of characters from start to stop in the text and
-- returns the protected string.
local function protect_range(text, start, stop)
   local s = text:sub(start, stop)
   local h = hash(s)
   PD.blocks[h] = s
   text = text:sub(1,start) .. h .. text:sub(stop)
   return text
end

-- Protect every part of the text that matches any of the patterns. The first
-- matching pattern is protected first, etc.
local function protect_matches(text, patterns)
   while true do
      local start, stop = find_first(text, patterns)
      if not start then break end
      text = protect_range(text, start, stop)
   end
   return text
end

-- Protects blocklevel tags in the specified text
local function protect(text)
   -- First protect potentially nested block tags
   text = protect_matches(text, map(PD.tags, block_pattern))
   -- Then protect block tags at the line level.
   text = protect_matches(text, map(PD.tags, line_pattern))
   -- Protect <hr> and comment tags
   text = protect_matches(text, {"\n<hr[^>]->[ \t]*\n"})
   text = protect_matches(text, {"\n<!%-%-.-%-%->[ \t]*\n"})
   return text
end

-- Returns true if the string s is a hash resulting from protection
local function is_protected(s)
   return PD.blocks[s]
end

-- Unprotects the specified text by expanding all the nonces
local function unprotect(text)
   for k,v in pairs(PD.blocks) do
      v = v:gsub("%%", "%%%%")
      text = text:gsub(k, v)
   end
   return text
end


----------------------------------------------------------------------
-- Block transform
----------------------------------------------------------------------

-- The block transform functions transform the text on the block level.
-- They work with the text as an array of lines rather than as individual
-- characters.

-- Returns true if the line is a ruler of (char) characters.
-- The line must contain at least three char characters and contain only spaces and
-- char characters.
local function is_ruler_of(line, char)
   if not line:match("^[ %" .. char .. "]*$") then return false end
   if not line:match("%" .. char .. ".*%" .. char .. ".*%" .. char) then return false end
   return true
end

-- Identifies the block level formatting present in the line
local function classify(line)
   local info = {line = line, text = line}

   if line:match("^    ") then
      info.type = "indented"
      info.outdented = line:sub(5)
      return info
   end

   for _,c in ipairs({'*', '-', '_', '='}) do
      if is_ruler_of(line, c) then
         info.type = "ruler"
         info.ruler_char = c
         return info
      end
   end

   if line == "" then
      info.type = "blank"
      return info
   end

   if line:match("^(#+)[ \t]*(.-)[ \t]*#*[ \t]*$") then
      local m1, m2 = line:match("^(#+)[ \t]*(.-)[ \t]*#*[ \t]*$")
      info.type = "header"
      info.level = m1:len()
      info.text = m2
      return info
   end

   if line:match("^ ? ? ?(%d+)%.[ \t]+(.+)") then
      local number, text = line:match("^ ? ? ?(%d+)%.[ \t]+(.+)")
      info.type = "list_item"
      info.list_type = "numeric"
      info.number = 0 + number
      info.text = text
      return info
   end

   if line:match("^ ? ? ?([%*%+%-])[ \t]+(.+)") then
      local bullet, text = line:match("^ ? ? ?([%*%+%-])[ \t]+(.+)")
      info.type = "list_item"
      info.list_type = "bullet"
      info.bullet = bullet
      info.text= text
      return info
   end

   if line:match("^>[ \t]?(.*)") then
      info.type = "blockquote"
      info.text = line:match("^>[ \t]?(.*)")
      return info
   end

   if is_protected(line) then
      info.type = "raw"
      info.html = unprotect(line)
      return info
   end

   info.type = "normal"
   return info
end

-- Find headers constisting of a normal line followed by a ruler and converts them to
-- header entries.
local function headers(array)
   local i = 1
   while i <= #array - 1 do
      if array[i].type  == "normal" and array[i+1].type == "ruler" and
         (array[i+1].ruler_char == "-" or array[i+1].ruler_char == "=") then
         local info = {line = array[i].line}
         info.text = info.line
         info.type = "header"
         info.level = iff(array[i+1].ruler_char == "=", 1, 2)
         table.remove(array, i+1)
         array[i] = info
      end
      i = i + 1
   end
   return array
end

-- Forward declarations
local block_transform, span_transform, encode_code

-- Convert lines to html code
local function blocks_to_html(lines, no_paragraphs)
   local out = {}
   local i = 1
   while i <= #lines do
      local line = lines[i]
      if line.type == "ruler" then
         table.insert(out, "<hr/>")
      elseif line.type == "raw" then
         table.insert(out, line.html)
      elseif line.type == "normal" then
         local s = line.line

         while i+1 <= #lines and lines[i+1].type == "normal" do
            i = i + 1
            s = s .. "\n" .. lines[i].line
         end

         if no_paragraphs then
            table.insert(out, span_transform(s))
         else
            table.insert(out, "<p>" .. span_transform(s) .. "</p>")
         end
      elseif line.type == "header" then
         local s = "<h" .. line.level .. ">" .. span_transform(line.text) .. "</h" .. line.level .. ">"
         table.insert(out, s)
      else
         table.insert(out, line.line)
      end
      i = i + 1
   end
   return out
end

-- Find list blocks and convert them to protected data blocks
local function lists(array, sublist)
   local function process_list(arr)
      local function any_blanks(arr)
         for i = 1, #arr do
            if arr[i].type == "blank" then return true end
         end
         return false
      end

      local function split_list_items(arr)
         local acc = {arr[1]}
         local res = {}
         for i=2,#arr do
            if arr[i].type == "list_item" then
               table.insert(res, acc)
               acc = {arr[i]}
            else
               table.insert(acc, arr[i])
            end
         end
         table.insert(res, acc)
         return res
      end

      local function process_list_item(lines, block)
         while lines[#lines].type == "blank" do
            table.remove(lines)
         end

         local itemtext = lines[1].text
         for i=2,#lines do
            itemtext = itemtext .. "\n" .. outdent(lines[i].line)
         end
         if block then
            itemtext = block_transform(itemtext, true)
            if not itemtext:find("<pre>") then itemtext = indent(itemtext) end
            return "    <li>" .. itemtext .. "</li>"
         else
            local lines = split(itemtext)
            lines = map(lines, classify)
            lines = lists(lines, true)
            lines = blocks_to_html(lines, true)
            itemtext = table.concat(lines, "\n")
            if not itemtext:find("<pre>") then itemtext = indent(itemtext) end
            return "    <li>" .. itemtext .. "</li>"
         end
      end

      local block_list = any_blanks(arr)
      local items = split_list_items(arr)
      local out = ""
      for _, item in ipairs(items) do
         out = out .. process_list_item(item, block_list) .. "\n"
      end
      if arr[1].list_type == "numeric" then
         return "<ol>\n" .. out .. "</ol>"
      else
         return "<ul>\n" .. out .. "</ul>"
      end
   end

   -- Finds the range of lines composing the first list in the array. A list
   -- starts with (^ list_item) or (blank list_item) and ends with
   -- (blank* $) or (blank normal).
   --
   -- A sublist can start with just (list_item) does not need a blank...
   local function find_list(array, sublist)
      local function find_list_start(array, sublist)
         if array[1].type == "list_item" then return 1 end
         if sublist then
            for i = 1,#array do
               if array[i].type == "list_item" then return i end
            end
         else
            for i = 1, #array-1 do
               if array[i].type == "blank" and array[i+1].type == "list_item" then
                  return i+1
               end
            end
         end
         return nil
      end
      local function find_list_end(array, start)
         local pos = #array
         for i = start, #array-1 do
            if array[i].type == "blank" and array[i+1].type ~= "list_item"
               and array[i+1].type ~= "indented" and array[i+1].type ~= "blank" then
               pos = i-1
               break
            end
         end
         while pos > start and array[pos].type == "blank" do
            pos = pos - 1
         end
         return pos
      end

      local start = find_list_start(array, sublist)
      if not start then return nil end
      return start, find_list_end(array, start)
   end

   while true do
      local start, stop = find_list(array, sublist)
      if not start then break end
      local text = process_list(splice(array, start, stop))
      local info = {
         line = text,
         type = "raw",
         html = text
      }
      array = splice(array, start, stop, {info})
   end

   -- Convert any remaining list items to normal
   for _,line in ipairs(array) do
      if line.type == "list_item" then line.type = "normal" end
   end

   return array
end

-- Find and convert blockquote markers.
local function blockquotes(lines)
   local function find_blockquote(lines)
      local start
      for i,line in ipairs(lines) do
         if line.type == "blockquote" then
            start = i
            break
         end
      end
      if not start then return nil end

      local stop = #lines
      for i = start+1, #lines do
         if lines[i].type == "blank" or lines[i].type == "blockquote" then
         elseif lines[i].type == "normal" then
            if lines[i-1].type == "blank" then stop = i-1 break end
         else
            stop = i-1 break
         end
      end
      while lines[stop].type == "blank" do stop = stop - 1 end
      return start, stop
   end

   local function process_blockquote(lines)
      local raw = lines[1].text
      for i = 2,#lines do
         raw = raw .. "\n" .. lines[i].text
      end
      local bt = block_transform(raw)
      if not bt:find("<pre>") then bt = indent(bt) end
      return "<blockquote>\n    " .. bt ..
         "\n</blockquote>"
   end

   while true do
      local start, stop = find_blockquote(lines)
      if not start then break end
      local text = process_blockquote(splice(lines, start, stop))
      local info = {
         line = text,
         type = "raw",
         html = text
      }
      lines = splice(lines, start, stop, {info})
   end
   return lines
end

-- Find and convert codeblocks.
local function codeblocks(lines)
   local function find_codeblock(lines)
      local start
      for i,line in ipairs(lines) do
         if line.type == "indented" then start = i break end
      end
      if not start then return nil end

      local stop = #lines
      for i = start+1, #lines do
         if lines[i].type ~= "indented" and lines[i].type ~= "blank" then
            stop = i-1
            break
         end
      end
      while lines[stop].type == "blank" do stop = stop - 1 end
      return start, stop
   end

   local function process_codeblock(lines)
      local raw = detab(encode_code(outdent(lines[1].line)))
      for i = 2,#lines do
         raw = raw .. "\n" .. detab(encode_code(outdent(lines[i].line)))
      end
      return "<pre><code>" .. raw .. "\n</code></pre>"
   end

   while true do
      local start, stop = find_codeblock(lines)
      if not start then break end
      local text = process_codeblock(splice(lines, start, stop))
      local info = {
         line = text,
         type = "raw",
         html = text
      }
      lines = splice(lines, start, stop, {info})
   end
   return lines
end

-- Perform all the block level transforms
function block_transform(text, sublist)
   local lines = split(text)
   lines = map(lines, classify)
   lines = headers(lines)
   lines = lists(lines, sublist)
   lines = codeblocks(lines)
   lines = blockquotes(lines)
   lines = blocks_to_html(lines)
   local text = table.concat(lines, "\n")
   return text
end

----------------------------------------------------------------------
-- Span transform
----------------------------------------------------------------------

-- Functions for transforming the text at the span level.

-- These characters may need to be escaped because they have a special
-- meaning in markdown.
local escape_chars = "'\\`*_{}[]()>#+-.!'"
local escape_table = {}

local function init_escape_table()
   escape_table = {}
   for i = 1,#escape_chars do
      local c = escape_chars:sub(i,i)
      escape_table[c] = hash(c)
   end
end

-- Adds a new escape to the escape table.
local function add_escape(text)
   if not escape_table[text] then
      escape_table[text] = hash(text)
   end
   return escape_table[text]
end

-- Encode backspace-escaped characters in the markdown source.
local function encode_backslash_escapes(t)
   for i=1,escape_chars:len() do
      local c = escape_chars:sub(i,i)
      t = t:gsub("\\%" .. c, escape_table[c])
   end
   return t
end

-- Escape characters that should not be disturbed by markdown.
local function escape_special_chars(text)
   local tokens = tokenize_html(text)

   local out = ""
   for _, token in ipairs(tokens) do
      local t = token.text
      if token.type == "tag" then
         -- In tags, encode * and _ so they don't conflict with their use in markdown.
         t = t:gsub("%*", escape_table["*"])
         t = t:gsub("%_", escape_table["_"])
      else
         t = encode_backslash_escapes(t)
      end
      out = out .. t
   end
   return out
end

-- Unescape characters that have been encoded.
local function unescape_special_chars(t)
   local tin = t
   for k,v in pairs(escape_table) do
      k = k:gsub("%%", "%%%%")
      t = t:gsub(v,k)
   end
   if t ~= tin then t = unescape_special_chars(t) end
   return t
end

-- Encode/escape certain characters inside Markdown code runs.
-- The point is that in code, these characters are literals,
-- and lose their special Markdown meanings.
function encode_code(s)
   s = s:gsub("%&", "&amp;")
   s = s:gsub("<", "&lt;")
   s = s:gsub(">", "&gt;")
   for k,v in pairs(escape_table) do
      s = s:gsub("%"..k, v)
   end
   return s
end

-- Handle backtick blocks.
local function code_spans(s)
   s = s:gsub("\\\\", escape_table["\\"])
   s = s:gsub("\\`", escape_table["`"])

   local pos = 1
   while true do
      local start, stop = s:find("`+", pos)
      if not start then return s end
      local count = stop - start + 1
      -- Find a matching numbert of backticks
      local estart, estop = s:find(string.rep("`", count), stop+1)
      local brstart = s:find("\n", stop+1)
      if estart and (not brstart or estart < brstart) then
         local code = s:sub(stop+1, estart-1)
         code = code:gsub("^[ \t]+", "")
         code = code:gsub("[ \t]+$", "")
         code = code:gsub(escape_table["\\"], escape_table["\\"] .. escape_table["\\"])
         code = code:gsub(escape_table["`"], escape_table["\\"] .. escape_table["`"])
         code = "<code>" .. encode_code(code) .. "</code>"
         code = add_escape(code)
         s = s:sub(1, start-1) .. code .. s:sub(estop+1)
         pos = start + code:len()
      else
         pos = stop + 1
      end
   end
   return s
end

-- Encode alt text... enodes &, and ".
local function encode_alt(s)
   if not s then return s end
   s = s:gsub('&', '&amp;')
   s = s:gsub('"', '&quot;')
   s = s:gsub('<', '&lt;')
   return s
end

-- Forward declaration for link_db as returned by strip_link_definitions.
local link_database

-- Handle image references
local function images(text)
   local function reference_link(alt, id)
      alt = encode_alt(alt:match("%b[]"):sub(2,-2))
      id = id:match("%[(.*)%]"):lower()
      if id == "" then id = text:lower() end
      link_database[id] = link_database[id] or {}
      if not link_database[id].url then return nil end
      local url = link_database[id].url or id
      url = encode_alt(url)
      local title = encode_alt(link_database[id].title)
      if title then title = " title=\"" .. title .. "\"" else title = "" end
      return add_escape ('<img src="' .. url .. '" alt="' .. alt .. '"' .. title .. "/>")
   end

   local function inline_link(alt, link)
      alt = encode_alt(alt:match("%b[]"):sub(2,-2))
      local url, title = link:match("%(<?(.-)>?[ \t]*['\"](.+)['\"]")
      url = url or link:match("%(<?(.-)>?%)")
      url = encode_alt(url)
      title = encode_alt(title)
      if title then
         return add_escape('<img src="' .. url .. '" alt="' .. alt .. '" title="' .. title .. '"/>')
      else
         return add_escape('<img src="' .. url .. '" alt="' .. alt .. '"/>')
      end
   end

   text = text:gsub("!(%b[])[ \t]*\n?[ \t]*(%b[])", reference_link)
   text = text:gsub("!(%b[])(%b())", inline_link)
   return text
end

-- Handle anchor references
local function anchors(text)
   local function reference_link(text, id)
      text = text:match("%b[]"):sub(2,-2)
      id = id:match("%b[]"):sub(2,-2):lower()
      if id == "" then id = text:lower() end
      link_database[id] = link_database[id] or {}
      if not link_database[id].url then return nil end
      local url = link_database[id].url or id
      url = encode_alt(url)
      local title = encode_alt(link_database[id].title)
      if title then title = " title=\"" .. title .. "\"" else title = "" end
      return add_escape("<a href=\"" .. url .. "\"" .. title .. ">") .. text .. add_escape("</a>")
   end

   local function inline_link(text, link)
      text = text:match("%b[]"):sub(2,-2)
      local url, title = link:match("%(<?(.-)>?[ \t]*['\"](.+)['\"]")
      title = encode_alt(title)
      url  = url or  link:match("%(<?(.-)>?%)") or ""
      url = encode_alt(url)
      if title then
         return add_escape("<a href=\"" .. url .. "\" title=\"" .. title .. "\">") .. text .. "</a>"
      else
         return add_escape("<a href=\"" .. url .. "\">") .. text .. add_escape("</a>")
      end
   end

   text = text:gsub("(%b[])[ \t]*\n?[ \t]*(%b[])", reference_link)
   text = text:gsub("(%b[])(%b())", inline_link)
   return text
end

-- Handle auto links, i.e. <http://www.google.com/>.
local function auto_links(text)
   local function link(s)
      return add_escape("<a href=\"" .. s .. "\">") .. s .. "</a>"
   end
   -- Encode chars as a mix of dec and hex entitites to (perhaps) fool
   -- spambots.
   local function encode_email_address(s)
      -- Use a deterministic encoding to make unit testing possible.
      -- Code 45% hex, 45% dec, 10% plain.
      local hex = {code = function(c) return "&#x" .. string.format("%x", c:byte()) .. ";" end, count = 1, rate = 0.45}
      local dec = {code = function(c) return "&#" .. c:byte() .. ";" end, count = 0, rate = 0.45}
      local plain = {code = function(c) return c end, count = 0, rate = 0.1}
      local codes = {hex, dec, plain}
      local function swap(t,k1,k2) local temp = t[k2] t[k2] = t[k1] t[k1] = temp end

      local out = ""
      for i = 1,s:len() do
         for _,code in ipairs(codes) do code.count = code.count + code.rate end
         if codes[1].count < codes[2].count then swap(codes,1,2) end
         if codes[2].count < codes[3].count then swap(codes,2,3) end
         if codes[1].count < codes[2].count then swap(codes,1,2) end

         local code = codes[1]
         local c = s:sub(i,i)
         -- Force encoding of "@" to make email address more invisible.
         if c == "@" and code == plain then code = codes[2] end
         out = out .. code.code(c)
         code.count = code.count - 1
      end
      return out
   end
   local function mail(s)
      s = unescape_special_chars(s)
      local address = encode_email_address("mailto:" .. s)
      local text = encode_email_address(s)
      return add_escape("<a href=\"" .. address .. "\">") .. text .. "</a>"
   end
   -- links
   text = text:gsub("<(https?:[^'\">%s]+)>", link)
   text = text:gsub("<(ftp:[^'\">%s]+)>", link)

   -- mail
   text = text:gsub("<mailto:([^'\">%s]+)>", mail)
   text = text:gsub("<([-.%w]+%@[-.%w]+)>", mail)
   return text
end

-- Encode free standing amps (&) and angles (<)... note that this does not
-- encode free >.
local function amps_and_angles(s)
   -- encode amps not part of &..; expression
   local pos = 1
   while true do
      local amp = s:find("&", pos)
      if not amp then break end
      local semi = s:find(";", amp+1)
      local stop = s:find("[ \t\n&]", amp+1)
      if not semi or (stop and stop < semi) or (semi - amp) > 15 then
         s = s:sub(1,amp-1) .. "&amp;" .. s:sub(amp+1)
         pos = amp+1
      else
         pos = amp+1
      end
   end

   -- encode naked <'s
   s = s:gsub("<([^a-zA-Z/?$!])", "&lt;%1")
   s = s:gsub("<$", "&lt;")

   -- what about >, nothing done in the original markdown source to handle them
   return s
end

-- Handles emphasis markers (* and _) in the text.
local function emphasis(text)
   for _, s in ipairs {"%*%*", "%_%_"} do
      text = text:gsub(s .. "([^%s][%*%_]?)" .. s, "<strong>%1</strong>")
      text = text:gsub(s .. "([^%s][^<>]-[^%s][%*%_]?)" .. s, "<strong>%1</strong>")
   end
   for _, s in ipairs {"%*", "%_"} do
      text = text:gsub(s .. "([^%s_])" .. s, "<em>%1</em>")
      text = text:gsub(s .. "(<strong>[^%s_]</strong>)" .. s, "<em>%1</em>")
      text = text:gsub(s .. "([^%s_][^<>_]-[^%s_])" .. s, "<em>%1</em>")
      text = text:gsub(s .. "([^<>_]-<strong>[^<>_]-</strong>[^<>_]-)" .. s, "<em>%1</em>")
   end
   return text
end

-- Handles line break markers in the text.
local function line_breaks(text)
   return text:gsub("  +\n", " <br/>\n")
end

-- Perform all span level transforms.
function span_transform(text)
   text = code_spans(text)
   text = escape_special_chars(text)
   text = images(text)
   text = anchors(text)
   text = auto_links(text)
   text = amps_and_angles(text)
   text = emphasis(text)
   text = line_breaks(text)
   return text
end

----------------------------------------------------------------------
-- Markdown
----------------------------------------------------------------------

-- Cleanup the text by normalizing some possible variations to make further
-- processing easier.
local function cleanup(text)
   -- Standardize line endings
   text = text:gsub("\r\n", "\n")  -- DOS to UNIX
   text = text:gsub("\r", "\n")    -- Mac to UNIX

   -- Convert all tabs to spaces
   text = detab(text)

   -- Strip lines with only spaces and tabs
   while true do
      local subs
      text, subs = text:gsub("\n[ \t]+\n", "\n\n")
      if subs == 0 then break end
   end

   return "\n" .. text .. "\n"
end

-- Strips link definitions from the text and stores the data in a lookup table.
local function strip_link_definitions(text)
   local linkdb = {}

   local function link_def(id, url, title)
      id = id:match("%[(.+)%]"):lower()
      linkdb[id] = linkdb[id] or {}
      linkdb[id].url = url or linkdb[id].url
      linkdb[id].title = title or linkdb[id].title
      return ""
   end

   local def_no_title = "\n ? ? ?(%b[]):[ \t]*\n?[ \t]*<?([^%s>]+)>?[ \t]*"
   local def_title1 = def_no_title .. "[ \t]+\n?[ \t]*[\"'(]([^\n]+)[\"')][ \t]*"
   local def_title2 = def_no_title .. "[ \t]*\n[ \t]*[\"'(]([^\n]+)[\"')][ \t]*"
   local def_title3 = def_no_title .. "[ \t]*\n?[ \t]+[\"'(]([^\n]+)[\"')][ \t]*"

   text = text:gsub(def_title1, link_def)
   text = text:gsub(def_title2, link_def)
   text = text:gsub(def_title3, link_def)
   text = text:gsub(def_no_title, link_def)
   return text, linkdb
end

-- Main markdown processing function
local function markdown(text)
   init_hash(text)
   init_escape_table()

   text = cleanup(text)
   text = protect(text)
   text, link_database = strip_link_definitions(text)
   text = block_transform(text)
   text = unescape_special_chars(text)
   return text
end

----------------------------------------------------------------------
-- End of module
----------------------------------------------------------------------

-- For compatibility, set markdown function as a global
-- _G.markdown = markdown

-- Class for parsing command-line options
local OptionParser = {}
OptionParser.__index = OptionParser

-- Creates a new option parser
function OptionParser:new()
   local o = {short = {}, long = {}}
   setmetatable(o, self)
   return o
end

-- Calls f() whenever a flag with specified short and long name is encountered
function OptionParser:flag(short, long, f)
   local info = {type = "flag", f = f}
   if short then self.short[short] = info end
   if long then self.long[long] = info end
end

-- Calls f(param) whenever a parameter flag with specified short and long name is encountered
function OptionParser:param(short, long, f)
   local info = {type = "param", f = f}
   if short then self.short[short] = info end
   if long then self.long[long] = info end
end

-- Calls f(v) for each non-flag argument
function OptionParser:arg(f)
   self.arg = f
end

-- Runs the option parser for the specified set of arguments. Returns true if all arguments
-- where successfully parsed and false otherwise.
function OptionParser:run(args)
   local pos = 1
   while pos <= #args do
      local arg = args[pos]
      if arg == "--" then
         for i=pos+1,#args do
            if self.arg then self.arg(args[i]) end
            return true
         end
      end
      if arg:match("^%-%-") then
         local info = self.long[arg:sub(3)]
         if not info then print("Unknown flag: " .. arg) return false end
         if info.type == "flag" then
            info.f()
            pos = pos + 1
         else
            local param = args[pos+1]
            if not param then print("No parameter for flag: " .. arg) return false end
            info.f(param)
            pos = pos+2
         end
      elseif arg:match("^%-") then
         for i=2,arg:len() do
            local c = arg:sub(i,i)
            local info = self.short[c]
            if not info then print("Unknown flag: -" .. c) return false end
            if info.type == "flag" then
               info.f()
            else
               if i == arg:len() then
                  local param = args[pos+1]
                  if not param then print("No parameter for flag: -" .. c) return false end
                  info.f(param)
                  pos = pos + 1
               else
                  local param = arg:sub(i+1)
                  info.f(param)
               end
               break
            end
         end
         pos = pos + 1
      else
         if self.arg then self.arg(arg) end
         pos = pos + 1
      end
   end
   return true
end

local function read_file(path, descr)
   local file = io.open(path) or error("Could not open " .. descr .. " file: " .. path)
   local contents = file:read("*a") or error("Could not read " .. descr .. " from " .. path)
   file:close()
   return contents
end

-- Handles the case when markdown is run from the command line
local function run_command_line(arg)
   -- Generate output for input s given options
   local function run(s, options)
      s = markdown(s)
      if not options.wrap_header then return s end
      local header
      if options.header then
         header = read_file(options.header, "header")
      else
         header = [[
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
<head>
    <meta http-equiv="content-type" content="text/html; charset=CHARSET" />
    <title>TITLE</title>
    <link rel="stylesheet" type="text/css" href="STYLESHEET" />
</head>
<body>
]]
         local title = options.title or s:match("<h1>(.-)</h1>") or s:match("<h2>(.-)</h2>") or
            s:match("<h3>(.-)</h3>") or "Untitled"
         header = header:gsub("TITLE", title)
         if options.inline_style then
            local style = read_file(options.stylesheet, "style sheet")
            header = header:gsub('<link rel="stylesheet" type="text/css" href="STYLESHEET" />',
               "<style type=\"text/css\"><!--\n" .. style .. "\n--></style>")
         else
            header = header:gsub("STYLESHEET", options.stylesheet)
         end
         header = header:gsub("CHARSET", options.charset)
      end
      local footer = "</body></html>"
      if options.footer then
         footer = read_file(options.footer, "footer")
      end
      return header .. s .. footer
   end

   -- Generate output path name from input path name given options.
   local function outpath(path, options)
      if options.append then return path .. ".html" end
      local m = path:match("^(.+%.html)[^/\\]+$") if m then return m end
      m = path:match("^(.+%.)[^/\\]*$") if m and path ~= m .. "html" then return m .. "html" end
      return path .. ".html"
   end

   -- Default commandline options
   local options = {
      wrap_header = true,
      header = nil,
      footer = nil,
      charset = "utf-8",
      title = nil,
      stylesheet = "default.css",
      inline_style = false
   }
   local help = [[
Usage: markdown.lua [OPTION] [FILE]
Runs the markdown text markup to HTML converter on each file specified on the
command line. If no files are specified, runs on standard input.

No header:
    -n, --no-wrap        Don't wrap the output in <html>... tags.
Custom header:
    -e, --header FILE    Use content of FILE for header.
    -f, --footer FILE    Use content of FILE for footer.
Generated header:
    -c, --charset SET    Specifies charset (default utf-8).
    -i, --title TITLE    Specifies title (default from first <h1> tag).
    -s, --style STYLE    Specifies style sheet file (default default.css).
    -l, --inline-style   Include the style sheet file inline in the header.
Generated files:
    -a, --append         Append .html extension (instead of replacing).
Other options:
    -h, --help           Print this help text.
    -t, --test           Run the unit tests.
]]

   local run_stdin = true
   local op = OptionParser:new()
   op:flag("n", "no-wrap", function () options.wrap_header = false end)
   op:param("e", "header", function (x) options.header = x end)
   op:param("f", "footer", function (x) options.footer = x end)
   op:param("c", "charset", function (x) options.charset = x end)
   op:param("i", "title", function(x) options.title = x end)
   op:param("s", "style", function(x) options.stylesheet = x end)
   op:flag("l", "inline-style", function() options.inline_style = true end)
   op:flag("a", "append", function() options.append = true end)
   op:flag("t", "test", function()
      local n = arg[0]:gsub("markdown%.lua", "markdown-tests.lua")
      local f = io.open(n)
      if f then
         f:close()
         package.loaded.markdown = markdown
         dofile(n)
      else
         error("Cannot find markdown-tests.lua")
      end
      run_stdin = false
   end)
   op:flag("h", "help", function() print(help) run_stdin = false end)
   op:arg(function(path)
      local s = read_file(path, "input")
      s = run(s, options)
      local file = io.open(outpath(path, options), "w") or error("Could not open output file: " .. outpath(path, options))
      file:write(s)
      file:close()
      run_stdin = false
   end
   )

   if not op:run(arg) then
      print(help)
      run_stdin = false
   end

   if run_stdin then
      local s = io.read("*a")
      s = run(s, options)
      io.write(s)
   end
end

-- If we are being run from the command-line, act accordingly
if arg and arg[0]:find("markdown%.lua$") then
   run_command_line(arg)
else
   return markdown
end
