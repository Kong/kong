local explicit = require 'lyaml.explicit'
local functional = require 'lyaml.functional'
local implicit = require 'lyaml.implicit'
local yaml = require 'yaml'

local anyof = functional.anyof
local find = string.find
local id = functional.id
local isnull = functional.isnull


local TAG_PREFIX = 'tag:yaml.org,2002:'


local function tag(name)
   return TAG_PREFIX .. name
end


local default = {
   -- Tag table to lookup explicit scalar conversions.
   explicit_scalar = {
      [tag 'bool'] = explicit.bool,
      [tag 'float'] = explicit.float,
      [tag 'int'] = explicit.int,
      [tag 'null'] = explicit.null,
      [tag 'str'] = explicit.str,
   },
   -- Order is important, so we put most likely and fastest nearer
   -- the top to reduce average number of comparisons and funcalls.
   implicit_scalar = anyof {
      implicit.null,
      implicit.octal,	-- subset of decimal, must come earlier
      implicit.decimal,
      implicit.float,
      implicit.bool,
      implicit.inf,
      implicit.nan,
      implicit.hexadecimal,
      implicit.binary,
      implicit.sexagesimal,
      implicit.sexfloat,
      id,
   },
}



-- Metatable for Dumper objects.
local dumper_mt = {
   __index = {
      -- Emit EVENT to the LibYAML emitter.
      emit = function(self, event)
         return self.emitter.emit(event)
      end,

      -- Look up an anchor for a repeated document element.
      get_anchor = function(self, value)
         local r = self.anchors[value]
         if r then
            self.aliased[value], self.anchors[value] = self.anchors[value], nil
         end
         return r
      end,

      -- Look up an already anchored repeated document element.
      get_alias = function(self, value)
         return self.aliased[value]
      end,

      -- Dump ALIAS into the event stream.
      dump_alias = function(self, alias)
         return self:emit {
            type = 'ALIAS',
            anchor = alias,
         }
      end,

      -- Dump MAP into the event stream.
      dump_mapping = function(self, map)
         local alias = self:get_alias(map)
         if alias then
            return self:dump_alias(alias)
         end

         self:emit {
            type = 'MAPPING_START',
            style = 'BLOCK',
         }

         local keys = {}
         for k in pairs(map) do
            keys[#keys + 1] = k
         end
         table.sort(keys)

         for i = 1,#keys do
            local k = keys[i]
            self:dump_node(k)
            self:dump_node(map[k])
         end
         return self:emit {type='MAPPING_END'}
      end,

      -- Dump SEQUENCE into the event stream.
      dump_sequence = function(self, sequence)
         local alias = self:get_alias(sequence)
         if alias then
            return self:dump_alias(alias)
         end

         self:emit {
            type   = 'SEQUENCE_START',
            anchor = self:get_anchor(sequence),
            style  = 'BLOCK',
         }
         for _, v in ipairs(sequence) do
            self:dump_node(v)
         end
         return self:emit {type='SEQUENCE_END'}
      end,

      -- Dump a null into the event stream.
      dump_null = function(self)
         return self:emit {
            type = 'SCALAR',
            value = '~',
            plain_implicit = true,
            quoted_implicit = true,
            style = 'PLAIN',
         }
      end,

      -- Dump VALUE into the event stream.
      dump_scalar = function(self, value)
         local alias = self:get_alias(value)
         if alias then
            return self:dump_alias(alias)
         end

         local anchor = self:get_anchor(value)
         local itsa = type(value)
         local style = 'PLAIN'
         if itsa == 'string' and self.implicit_scalar(value) ~= value then
            -- take care to round-trip strings that look like scalars
            style = 'SINGLE_QUOTED'
         elseif value == math.huge then
            value = '.inf'
         elseif value == -math.huge then
            value = '-.inf'
         elseif value ~= value then
            value = '.nan'
         elseif itsa == 'number' or itsa == 'boolean' then
            value = tostring(value)
         elseif itsa == 'string' and find(value, '\n') then
            style = 'LITERAL'
         end
         return self:emit {
            type = 'SCALAR',
            anchor = anchor,
            value = value,
            plain_implicit = true,
            quoted_implicit = true,
            style = style,
         }
      end,

      -- Decompose NODE into a stream of events.
      dump_node = function(self, node)
         local itsa = type(node)
         if isnull(node) then
            return self:dump_null()
         elseif itsa == 'string' or itsa == 'boolean' or itsa == 'number' then
            return self:dump_scalar(node)
         elseif itsa == 'table' then
            -- Something is only a sequence if its keys start at 1
            -- and are consecutive integers without any jumps.
            local prior_key = 0
            local is_pure_sequence = true
            local i, _ = next(node, nil)
            while i and is_pure_sequence do
              if type(i) ~= "number" or (prior_key + 1 ~= i) then
                is_pure_sequence = false -- breaks the loop
              else
                prior_key = i
                i, _ = next(node, prior_key)
              end
            end
            if is_pure_sequence then
               -- Only sequentially numbered integer keys starting from 1.
               return self:dump_sequence(node)
            else
               -- Table contains non sequential integer keys or mixed keys.
               return self:dump_mapping(node)
            end
         else -- unsupported Lua type
            error("cannot dump object of type '" .. itsa .. "'", 2)
         end
      end,

      -- Dump DOCUMENT into the event stream.
      dump_document = function(self, document)
         self:emit {type='DOCUMENT_START'}
         self:dump_node(document)
         return self:emit {type='DOCUMENT_END'}
      end,
   },
}


local function Dumper(opts)
   local anchors = {}
   for k, v in pairs(opts.anchors) do
      anchors[v] = k
   end
   local object = {
      aliased = {},
      anchors = anchors,
      emitter = yaml.emitter(),
      implicit_scalar = opts.implicit_scalar,
   }
   return setmetatable(object, dumper_mt)
end


--- Dump a list of Lua tables to an equivalent YAML stream.
-- @tparam table documents a sequence of Lua tables.
-- @tparam[opt] dumper_opts opts initialisation options
-- @treturn string equivalest YAML stream
local function lyaml_sorted_dump(documents, opts)
   opts = opts or {}

   -- backwards compatibility
   if opts.anchors == nil and opts.implicit_scalar == nil then
      opts = {anchors=opts}
   end

   local dumper = Dumper {
      anchors = opts.anchors or {},
      implicit_scalar = opts.implicit_scalar or default.implicit_scalar,
   }

   dumper:emit {type='STREAM_START', encoding='UTF8'}
   for _, document in ipairs(documents) do
      dumper:dump_document(document)
   end
   local _, stream = dumper:emit {type='STREAM_END'}
   return stream
end


return lyaml_sorted_dump
