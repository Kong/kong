-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local xmlua = require "xmlua"
local document = require "xmlua.document"
local ffi = require "ffi"
local datafile = require "datafile"

local xml2 = ffi.load "xml2"
local xslt = ffi.load "xslt"

ffi.cdef([[
  typedef struct _xsltStylesheet* xsltStylesheetPtr;
  typedef struct _xsltTransformContext* xsltTransformContextPtr;

  xsltStylesheetPtr xsltParseStylesheetDoc(xmlDocPtr doc);
  void xsltFreeStylesheet(xsltStylesheetPtr);

  xsltTransformContextPtr xsltNewTransformContext(xsltStylesheetPtr stylesheet,
                                                  xmlDocPtr doc);
  void xsltFreeTransformContext(xsltTransformContextPtr ctxt);

  xmlDocPtr xsltApplyStylesheetUser(xsltStylesheetPtr stylesheet,
                                    xmlDocPtr doc,
                                    const char** params,
                                    const char* output,
                                    void* profile,
                                    xsltTransformContextPtr userCtxt);

  xmlDocPtr xmlParseFile(const char* filename);
  xmlDocPtr xmlNewDoc(const char* version);
  xmlNodePtr xmlDocCopyNode(xmlNodePtr node,
                            xmlDocPtr doc,
                            int extended);
  xmlNodePtr xmlDocSetRootElement(xmlDocPtr doc,
                                  xmlNodePtr root);
  void xmlFreeDoc(xmlDocPtr);
]])

local function new(name)
  local path = "xml/" .. name .. ".xslt"
  local f, err = datafile.open(path)
  if not f then
    return nil, err
  end

  local document = xmlua.XML.parse(f:read("*a"))
  f:close()

  -- need to make a copy of doc.document because the parsed stylesheet claims
  -- ownership of the document that it was created from and frees it when it is
  -- freed by xsltFreeStylesheet
  local copied_document = xml2.xmlNewDoc("1.0")
  local root_node = xml2.xmlDocCopyNode(document:root().node, copied_document, 1)
  xml2.xmlDocSetRootElement(copied_document, root_node)

  local stylesheet = xslt.xsltParseStylesheetDoc(copied_document)
  ffi.gc(stylesheet, xslt.xsltFreeStylesheet)

  return {
    stylesheet = stylesheet,
  }
end

local function make_parameter_table()
  return setmetatable({}, {
      __newindex = function (t, key, value)
        if type(value) == "string" then
          if string.find(value, "'") then
            error("cannot use apostrophe in string value passed to xslt")
          end
          rawset(t, key, "'" .. value .. "'")
        elseif type(value) == "number" then
          rawset(t, key, value)
        else
          error("cannot pass value of type " .. type(value) .. " as parameter to xslt")
        end
      end,
  })
end

local function apply(self, doc, params)
  local input_document
  if doc then
    input_document = doc.document
  else
    input_document = xml2.xmlNewDoc("1.0")
    ffi.gc(input_document, xml2.xmlFreeDoc)
  end

  local param_pairs = {}
  for k, v in pairs(params) do
    param_pairs[#param_pairs + 1] = k
    param_pairs[#param_pairs + 1] = v
  end

  local params_array = ffi.new("const char*[?]", #param_pairs + 1, param_pairs)
  params_array[#param_pairs] = nil

  local context = xslt.xsltNewTransformContext(self.stylesheet, input_document)
  ffi.gc(context, xslt.xsltFreeTransformContext)

  local result = xslt.xsltApplyStylesheetUser(self.stylesheet, input_document, params_array, ffi.NULL, ffi.NULL, context)
  if result == nil then
    return nil
  end
  ffi.gc(result, xml2.xmlFreeDoc)

  return document.new(result)
end

return {
  new = new,
  apply = apply,
  make_parameter_table = make_parameter_table,
}
