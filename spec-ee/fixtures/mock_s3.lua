-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local query = ngx.req.get_uri_args()
local headers = ngx.req.get_headers()
local full_path = ngx.var.uri
local bucket, path = full_path:match("^/([^/]+)/?(.*)")
if ngx.req.get_method() == "PUT" then
  ngx.shared.objects:set(full_path, body or "")

  local date = headers["X-Amz-Date"] or "20231221T000000Z"
  local etag = headers["ETag"] or headers["X-Amz-Content-Sha256"] or "d41d8cd98f00b204e9800998ecf8427e"
  local content_type = headers["Content-Type"] or "application/octet-stream"

  ngx.shared.metadata:set(full_path, table.concat(
    {date, etag, content_type}, "\n"
  ))        

  return ngx.exit(200)
elseif ngx.req.get_method() == "GET" then
  local prefix = query["prefix"]
  local list_type = query["list-type"]
  if not path or path == "" then
    if list_type == "2" then
      local contents = {}

      local metadata = ngx.shared.metadata:get_keys()

      for _, fpath in ipairs(metadata) do
        local meta = ngx.shared.metadata:get(fpath)
        local date, etag, content_type = meta:match("^(.-)\n(.-)\n(.-)$")
        local key = fpath:sub(#bucket + 3)
        if key:sub(1, #prefix) == prefix then
          table.insert(contents, string.format(
            [[<Contents>
            <Key>]] .. key .. [[</Key>
            <LastModified>]] .. date .. [[</LastModified>
            <ETag>"]] .. etag .. [["</ETag>
            <Size>0</Size>
            <StorageClass>STANDARD</StorageClass>
          </Contents>]]
          ))
        end
      end

      local body = [[<?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <Name>]] .. bucket .. [[</Name>
          <Prefix>]] .. prefix .. [[</Prefix>
          <IsTruncated>false</IsTruncated>
          ]] .. table.concat(contents) .. [[
        </ListBucketResult>
      ]]
      ngx.header["Content-Type"] = "application/xml"
      ngx.header["Content-Length"] = #body
      ngx.print(body)
      return ngx.exit(200)
    end
  else
    local body = ngx.shared.objects:get(full_path)
    if not body then
      return ngx.exit(404)
    end
    ngx.header["Content-Length"] = #body
    ngx.print(body)
    local meta = ngx.shared.metadata:get(full_path)
    local date, etag, content_type = meta:match("^(.-)\n(.-)\n(.-)$")
    ngx.header["Last-Modified"] = date
    ngx.header["ETag"] = etag
    ngx.header["Content-Type"] = content_type
    return ngx.exit(200)
  end
end
