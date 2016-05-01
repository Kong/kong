--[[
  Copyright 2016 Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]

--
-- Cache implementation for API Gateway
-- User: ddascal
-- Date: 31/01/16
--

local _M = { version = "0.1.1" }

local function __init(init_obj)
    init_obj.__cache_stores = {}
end

function _M:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self

    __init(o)

    return o
end

---
-- See if the the cache already exists inside the cache store
-- @param store
--
function _M:hasStore(store)
    if (store == nil) then
        ngx.log(ngx.DEBUG, "Store to be compared is nil")
        return false
    end
    for _, cache_store in ipairs(self.__cache_stores) do
        if (cache_store == nil) then
            ngx.log(ngx.DEBUG, "Store from cache store is nil" )
            return false
        end
        ngx.log(ngx.DEBUG, "Comparing store named: ", store:getName(), " with existing store named: ", cache_store:getName())
        if (cache_store:getName() == store:getName()) then
            return true
        end
    end
    return false
end

--- Adds a cache into the cache. The order in which the caches are added
-- is important when reading / writing from/to cache.
-- @param store An instance of kong.plugins.aws-lambda.api-gateway.cache.store object.
--
function _M:addStore(store)
    if (store == nil) then
        ngx.log(ngx.WARN, "Attempt to add a nil cache store")
        return nil
    end

    if (self:hasStore(store)) then
       ngx.log(ngx.WARN, "Attempt to add a cache store that already exists: ", store:getName())
       return nil
    end

    local count = #self.__cache_stores
    self.__cache_stores[count + 1] = store
    return self.__cache_stores
end

--- Returns all cache stores
--
function _M:getStores()
    return self.__cache_stores
end

--- Returns the value of the cached key along with the name of the cache store
-- The cache stores are searched in order that they were added.
-- If an element has been expired in the cache, but it exists in another cache, then the other upper cache stores are re-populated.
-- @param key Cache lookup key
--
function _M:get(key)
    if (key == nil) then
        ngx.log(ngx.WARN, "Attempting to get a nil key from cache")
        return nil, nil
    end
    local store_idx = 0
    for idx, cache_store in ipairs(self.__cache_stores) do
        local val = cache_store:get(key)
        if (val ~= nil) then
            -- repopulate the upper cache stores
            for i = 1, idx - 1 do
                self.__cache_stores[i]:put(key,val)
            end
            ngx.log(ngx.DEBUG, "Returning the cached value for ", tostring(key), " from ", tostring(cache_store:getName()))
            return val, cache_store:getName()
        end
    end
    return nil, nil
end

--- Stores a new item in the cache. If the item already exists it's overwritten.
-- The cache stores
-- @param key The cached key
-- @param value The value of the key
--
function _M:put(key, value)
    if (key == nil) then
        ngx.log(ngx.WARN, "Attempting to put a nil key in cache")
        return nil
    end

    for _, cache_store in ipairs(self.__cache_stores) do
        cache_store:put(key, value)
    end
end

return _M
