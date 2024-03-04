local table_insert = table.insert
local table_remove = table.remove
local table_new = require("table.new")
local table_clear = require("table.clear")


local error = error
local setmetatable = setmetatable

local array_pool = {}

local _M = {}

local meta_table = {
    __index = _M,
}


function _M.next(array, index)
    if index == nil then
        index = 0
    end

    if array.nelts < index then
        return nil
    end

    if index + 1 > array.nelts then
        return nil
    end

    return index + 1, array.elts[index]
end


function _M:length()
    return self.last - self.first + 1
end



function _M:is_empty()
    return self.first > self.last
end


function _M:push_left (value)
    local first = self.first - 1
    self.first = first
    self.elts[first] = value
end


function _M:push_right(value)
    local last = self.last + 1
    self.last = last
    self.elts[last] = value
end


function _M:pop_left()
    local first = self.first

    if first > self.last then
        error("list is empty")
    end

    local value = self.elts[first]
    self.elts[first] = nil
    self.first = first + 1
    return value
end


function _M:pop_right()
    local last = self.last

    if self.first > last then
        error("list is empty")
    end

    local value = self.elts[last]
    self.elts[last] = nil
    self.last = last - 1
    return value
end


function _M.new(n)
    if n == nil then
        n = 8
    end

    local self = table_remove(array_pool)

    if self then
        return self
    end

    self = {
        elts = table_new(n, 0),
        first = 0,
        last = -1,
    }

    return setmetatable(self, meta_table)
end


function _M:release()
    table_clear(self.elts)
    self.first = 0
    self.last = -1
    table_insert(array_pool, self)
end


function _M.merge(dst, src)
    if src == nil then
        return
    end

    while not src:is_empty() do
        dst:push_left(src:pop_left())
    end
end


return _M