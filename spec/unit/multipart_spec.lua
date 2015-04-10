local multipart = require "kong.tools.multipart"
local utils = require "kong.tools.utils"

describe("Multipart #tools", function()

  it("should decode a multipart body", function() 

    local boundary = "AaB03x"
    local body = [[
--AaB03x
Content-Disposition: form-data; name="submit-name"

Larry
--AaB03x
Content-Disposition: form-data; name="files"; filename="file1.txt"
Content-Type: text/plain

... contents of file1.txt ...
hello
--AaB03x--]]

    local t = multipart.decode(body, boundary)
    assert.truthy(t)

    -- Check internals
    local index = t.indexes["submit-name"]
    assert.truthy(index)
    assert.are.same(1, index)
    assert.truthy(t.data[index])
    assert.truthy(t.data[index].name)
    assert.are.same("submit-name", t.data[index].name)
    assert.truthy(t.data[index].headers)
    assert.are.same({"Content-Disposition: form-data; name=\"submit-name\""}, t.data[index].headers)
    assert.are.same(1, utils.table_size(t.data[index].headers))
    assert.truthy(t.data[index].value)
    assert.are.same("Larry", t.data[index].value)

    index = t.indexes["files"]
    assert.truthy(index)
    assert.are.same(2, index)
    assert.truthy(t.data[index])
    assert.truthy(t.data[index].name)
    assert.are.same("files", t.data[index].name)
    assert.truthy(t.data[index].headers)
    assert.are.same({"Content-Disposition: form-data; name=\"files\"; filename=\"file1.txt\"", "Content-Type: text/plain"}, t.data[index].headers)
    assert.are.same(2, utils.table_size(t.data[index].headers))
    assert.truthy(t.data[index].value)
    assert.are.same("... contents of file1.txt ...\r\nhello", t.data[index].value)
  end)

  it("should encode a multipart body", function() 
    local boundary = "AaB03x"
    local body = [[
--AaB03x
Content-Disposition: form-data; name="submit-name"\r\n

Larry
--AaB03x
Content-Disposition: form-data; name="files"; filename="file1.txt"
Content-Type: text/plain

... contents of file1.txt ...
hello
--AaB03x--]]

    local t = multipart.decode(body, boundary)
    assert.truthy(t)

    local data = multipart.encode(t, boundary)

    -- The strings should be the same, but \n needs to be replaced with \r\n
    local replace_new_lines, _ = string.gsub(body, "\n", "\r\n")
    assert.are.same(data, replace_new_lines)
  end)

  it("should delete a parameter", function() 
    local boundary = "AaB03x"
    local body = [[
--AaB03x
Content-Disposition: form-data; name="submit-name"

Larry
--AaB03x
Content-Disposition: form-data; name="files"; filename="file1.txt"
Content-Type: text/plain

... contents of file1.txt ...
hello
--AaB03x--]]

    local inspect = require "inspect"
    local t = multipart.decode(body, boundary)
    assert.truthy(t)

    table.remove(t.data, t.indexes["submit-name"])

    local data = multipart.encode(t, boundary)

    -- The strings should be the same, but \n needs to be replaced with \r\n
    local replace_new_lines, _ = string.gsub([[
--AaB03x
Content-Disposition: form-data; name="files"; filename="file1.txt"
Content-Type: text/plain

... contents of file1.txt ...
hello
--AaB03x--]], "\n", "\r\n")
    assert.are.same(data, replace_new_lines)
  end)

  it("should delete the last parameter", function() 
    local boundary = "AaB03x"
    local body = [[
--AaB03x
Content-Disposition: form-data; name="submit-name"

Larry
--AaB03x
Content-Disposition: form-data; name="files"; filename="file1.txt"
Content-Type: text/plain

... contents of file1.txt ...
hello
--AaB03x--]]

    local inspect = require "inspect"
    local t = multipart.decode(body, boundary)
    assert.truthy(t)

    table.remove(t.data, t.indexes["files"])

    local data = multipart.encode(t, boundary)

    -- The strings should be the same, but \n needs to be replaced with \r\n
    local replace_new_lines, _ = string.gsub([[
--AaB03x
Content-Disposition: form-data; name="submit-name"

Larry
--AaB03x--]], "\n", "\r\n")
    assert.are.same(data, replace_new_lines)
  end)

end)