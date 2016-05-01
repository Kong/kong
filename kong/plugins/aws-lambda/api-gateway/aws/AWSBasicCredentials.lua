--[[
  Copyright 2016 Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]

--
-- Basic Credentials provider using access_key and secret.
-- User: ddascal
-- Date: 4/10/16
-- Time: 21:26
--

local _M = {}

---
-- @param o Init object
-- o.access_key                       -- required. AWS Access Key Id
-- o.secret_key                       -- required. AWS Secret Access Key
--
function _M:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if (o ~= nil) then
        self.aws_secret_key = o.secret_key
        self.aws_access_key = o.access_key
    end
    return o
end

function _M:getSecurityCredentials()
    return self.aws_access_key, self.aws_secret_key
end

return _M

