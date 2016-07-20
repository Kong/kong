local cjson = require "cjson"
local cjson_safe = require "cjson.safe"
local string = require "string"

local JsonValidator = {}

----------------------
-- Utility function --
----------------------

-- Determine with a Lua table can be treated as an array.
-- Explicitly returns "not an array" for very sparse arrays.
-- Returns:
-- -1   Not an array
-- 0    Empty table
-- >0   Highest index in the array
local function is_array(table)
    local max = 0
    local count = 0
    for k, v in pairs(table) do
        if type(k) == "number" then
            if k > max then max = k end
            count = count + 1
        else
            return -1
        end
    end
    if max > count * 2 then
        return -1
    end

    return max
end

local function validateJson(json, array_element_count, object_entry_count, object_entry_name_length, string_value_length)
    if type(json) == "table" then
        --------------------------------------
        -- Validate the array element count --
        --------------------------------------
        if array_element_count > 0 then
            local array_children = is_array(json)
            if array_children > array_element_count then
                return false, "JSONThreatProtection[ExceededArrayElementCount]: Exceeded array element count, max " .. array_element_count .. " allowed, found " .. array_children .. "."
            end
        end

        local children_count = 0
        for k,v in pairs(json) do
            children_count = children_count + 1
            ------------------------------------
            -- Validate the entry name length --
            ------------------------------------
            if object_entry_name_length > 0 then
                if string.len(k) > object_entry_name_length then
                    return false, "JSONThreatProtection[ExceededObjectEntryNameLength]: Exceeded object entry name length, max " .. object_entry_name_length .. " allowed, found " .. string.len(k) .. " (" .. k .. ")."
                end
            end

            -- recursively repeat the same procedure
            local result, message = validateJson(v, array_element_count, object_entry_count, object_entry_name_length, string_value_length)
            if result == false then
                return false, message
            end
        end

        -------------------------------------
        -- Validate the object entry count --
        -------------------------------------
        if object_entry_count > 0 then
            if children_count > object_entry_count then
                return false, "JSONThreatProtection[ExceededObjectEntryCount]: Exceeded object entry count, max " .. object_entry_count .. " allowed, found " .. children_count .. "."
            end
        end

    else
        --------------------------------------
        -- Validate the string value length --
        --------------------------------------
        if string_value_length > 0 then
            if string.len(json) > string_value_length then
                return false, "JSONThreatProtection[ExceededStringValueLength]: Exceeded string value length, max " .. string_value_length .. " allowed, found " .. string.len(json) .. " (" .. json .. ")."
            end
        end
    end

    return true, ""
end

------------------------------
-- Validator implementation --
------------------------------

function JsonValidator.execute(body, container_depth, array_element_count, object_entry_count, object_entry_name_length, string_value_length)

    ----------------------------
    -- Validate if valid JSON --
    ----------------------------
    local valid = cjson_safe.decode(body)
    if not valid then
        return true, ""
    end

    ----------------------------------
    -- Validate the container depth --
    ----------------------------------
    if container_depth > 0 then
        cjson.decode_max_depth(container_depth)
    end

    local status, json = pcall(cjson.decode, body)
    if not status then
        return false, "JSONThreatProtection[ExceededContainerDepth]: Exceeded container depth, max " .. container_depth .. " allowed."
    end

    return validateJson(json, array_element_count, object_entry_count, object_entry_name_length, string_value_length)
end

return JsonValidator
