-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local xmlua = require "xmlua"
local datafile = require "datafile"
local ffi = require "ffi"

local loaded, xml2 = pcall(ffi.load, "xml2")
if not loaded then
  xml2 = ffi.load("libxml2.so.2")
end

ffi.cdef([[
  typedef struct _xmlDoc* xmlDocPtr;
  typedef struct _xmlSchema* xmlSchemaPtr;
  typedef struct _xmlSchemaParserCtxt* xmlSchemaParserCtxtPtr;
  typedef struct _xmlSchemaValidCtxt* xmlSchemaValidCtxtPtr;

  xmlSchemaParserCtxtPtr xmlSchemaNewDocParserCtxt(xmlDocPtr doc);
  void xmlSchemaFreeParserCtxt(xmlSchemaParserCtxtPtr ctxt);
  xmlSchemaPtr xmlSchemaParse(xmlSchemaParserCtxtPtr ctxt);
  void xmlSchemaFree(xmlSchemaPtr schema);

  xmlSchemaValidCtxtPtr xmlSchemaNewValidCtxt(xmlSchemaPtr schema);
  void xmlSchemaFreeValidCtxt(xmlSchemaValidCtxtPtr ctxt);
  int xmlSchemaValidateDoc(xmlSchemaValidCtxtPtr ctxt, xmlDocPtr instance);
  ]])


local function read_doc(path)
  local f, err = assert(datafile.open(path))
  if not f then
    return nil, err
  end

  local document = xmlua.XML.parse(f:read("*a"))
  f:close()
  return document
end

local function new(path, catalog)
  local schema_doc = assert(read_doc(path))
  local parser_context = xml2.xmlSchemaNewDocParserCtxt(schema_doc.document)
  if parser_context == nil then
    error("Cannot create XML schema parser context")
  end
  ffi.gc(parser_context, xml2.xmlSchemaFreeParserCtxt)
  local schema = xml2.xmlSchemaParse(parser_context)
  if schema == nil then
    error("Cannot parse XML schema")
  end
  ffi.gc(schema, xml2.xmlSchemaFree)

  return {
    schema = schema
  }
end


local function validate(self, doc)
  if type(doc) == "table" then
    doc = doc.document
  end

  local validation_context = xml2.xmlSchemaNewValidCtxt(self.schema)
  ffi.gc(validation_context, xml2.xmlSchemaFreeValidCtxt)
  local result = xml2.xmlSchemaValidateDoc(validation_context, doc)

  return result == 0
end

return {
  new = new,
  validate = validate,
}
