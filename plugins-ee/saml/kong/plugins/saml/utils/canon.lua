-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local xmlua     = require "xmlua"
local libxml2   = require "xmlua.libxml2"
local stringx   = require "pl.stringx"

local ffi = require("ffi")
local loaded, xml2 = pcall(ffi.load, "xml2")
if not loaded then
  xml2 = ffi.load("libxml2.so.2")
end

if not pcall(ffi.typeof, "struct _xmlOutputBuffer") then
  ffi.cdef[[
typedef unsigned char xmlChar;

typedef struct _xmlBuffer xmlBuffer;
typedef xmlBuffer *xmlBufferPtr;

typedef struct _xmlCharEncodingHandler xmlCharEncodingHandler;
typedef xmlCharEncodingHandler *xmlCharEncodingHandlerPtr;

typedef int (*xmlOutputWriteCallback) (void * context, const char * buffer, int len);
typedef int (*xmlOutputCloseCallback) (void * context);

struct _xmlOutputBuffer {
  void*                   context;
  xmlOutputWriteCallback  writecallback;
  xmlOutputCloseCallback  closecallback;

  xmlCharEncodingHandlerPtr encoder; /* I18N conversions to UTF-8 */

  xmlBufferPtr buffer;    /* Local buffer encoded in UTF-8 or ISOLatin */
  xmlBufferPtr conv;      /* if encoder != NULL buffer for output */
  int written;            /* total number of byte written */
  int error;
};

typedef struct _xmlOutputBuffer xmlOutputBuffer;
typedef xmlOutputBuffer *xmlOutputBufferPtr;

xmlOutputBufferPtr xmlAllocOutputBuffer (xmlCharEncodingHandlerPtr encoder);
xmlOutputBufferPtr xmlOutputBufferCreateBuffer  (xmlBufferPtr buffer, xmlCharEncodingHandlerPtr encoder);
int xmlOutputBufferClose        (xmlOutputBufferPtr out);
int xmlC14NDocSaveTo(xmlDocPtr doc,
                     xmlNodeSetPtr nodes,
                     int mode, /* a xmlC14NMode */
                     xmlChar **inclusive_ns_prefixes,
                     int with_comments,
                     xmlOutputBufferPtr buf);
xmlDocPtr xmlNewDoc (const xmlChar * version);
void xmlFreeDoc(xmlDocPtr cur);
xmlNodePtr xmlDocCopyNode(xmlNodePtr node,
                          xmlDocPtr doc,
                          int extended);
xmlNodePtr xmlDocSetRootElement(xmlDocPtr doc,
                                xmlNodePtr root);
    ]]
end

local _M = {}

local function xmlOutputBufferCreate(buffer)
  return ffi.gc(xml2.xmlOutputBufferCreateBuffer(buffer, nil), xml2.xmlOutputBufferClose)
end

-- perform canonical serialization for the given XML element or document
function _M:c14n(thing, inclusive_ns_prefixes)
  local document

  if type(thing) == "string" then
    document = xmlua.XML.parse(thing).document

  elseif thing.node and thing.node.type ~= ffi.C.XML_ELEMENT_NODE then
    document = thing.doc

  elseif thing.node and thing.node.type ~= ffi.C.XML_DOCUMENT_NODE then

    document = xml2.xmlNewDoc("1.0")
    local root = xml2.xmlDocCopyNode(thing.node, document, 1)
    ffi.gc(document, xml2.xmlFreeDoc)
    if root == nil then
      return nil, "Cannot copy element to new document for canonicalization"
    end
    xml2.xmlDocSetRootElement(document, root)
  else
    return nil, "Don't know how to canonicalize provided value"
  end

  local inclusive_ns_prefixes_array = nil
  if inclusive_ns_prefixes then
    local parsed_prefixes = stringx.split(inclusive_ns_prefixes, " ")
    inclusive_ns_prefixes_array = ffi.new("xmlChar*[?]", #parsed_prefixes+1)

    for i, namespace in ipairs(parsed_prefixes) do
      local c_ns = ffi.new("unsigned char[?]", #namespace+1, namespace)
      ffi.copy(c_ns, namespace)
      inclusive_ns_prefixes_array[i-1] = c_ns
    end

    inclusive_ns_prefixes_array[#parsed_prefixes] = nil
  end

  local buffer = libxml2.xmlBufferCreate()
  local output_buffer = xmlOutputBufferCreate(buffer)

  xml2.xmlC14NDocSaveTo(document, nil, 1, inclusive_ns_prefixes_array, 0, output_buffer)

  local content = libxml2.xmlBufferGetContent(buffer)
  return content
end

return _M
