setmetatable(_G, nil)

local cjson_encode = require("cjson.safe").encode
local table_insert = table.insert

local USAGE = [[

A tool to compare two schema.lua files, and output the difference in json format

Usage:
    resty ./scripts/schema-diff.lua <old_schema> <new_schema>

Example:
    resty ./scripts/schema-diff.lua old_schema.lua new_schema.lua

Output:
    {   "added": [{"path": "path.to.field1"} ... ],
        "removed": [{"path": "path.to.field"2} ...],
        "changed": [{"path": "path.to.field3"} ... ]
    }
]]

local function print_log(...)
    -- print(...)
end


-- Get first key value pair of a table
-- for json compatibility reason, each item in schema table is a table
-- instead of a key value pair
-- so we need to convert it to a key value pair
local function first_pair_of(table)
    -- return nil if table is empty
    local k, v = next(table)
    return k, v
end


local function find_field(fields, key)
    for _, item in pairs(fields) do
        local k, v = next(item)
        if k == key then
            return v
        end
    end
    return nil
end

-- return true if two tables are equal (deeply)
-- WARN: if value is a function or userdata, value will be ignored
local function deep_eq(t1, t2)
    if type(t1) ~= "table" or type(t2) ~= "table" then
        return t1 == t2
    end

    local t1_keys = {}
    local t2_keys = {}

    for k, v in pairs(t1) do
        if type(v) ~= "function" and type(v) ~= "userdata" then
            t1_keys[k] = v
        end
    end

    for k, v in pairs(t2) do
        if type(v) ~= "function" and type(v) ~= "userdata" then
            t2_keys[k] = v
        end
    end

    if #t1_keys ~= #t2_keys then
        return false
    end

    for k, v in pairs(t1_keys) do
        if t2_keys[k] == nil then
            return false
        end

        if not deep_eq(v, t2_keys[k]) then
            return false
        end
    end

    return true
end

local function in_place_merge(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k] or false) == "table" then
                in_place_merge(v, dst[k])
            else
                dst[k] = v
            end
        else
            dst[k] = v
        end
    end
    return dst
end

local function diff_schema_fields(old_fields, new_fields, prefix)
    print_log("checking: " .. prefix)
    local added = {}
    local removed = {}
    local changed = {}

    for _, item in pairs(old_fields) do
        local oldk, oldv = first_pair_of(item)
        local newv = find_field(new_fields, oldk)
        local sub_prefix = prefix .. oldk
        local is_nested_schema = type(oldv) == "table" 
            and oldv["fields"] ~= nil
            and oldv["type"] == "record"

        if is_nested_schema then
            local oldv_fields = oldv["fields"]
            local newv_fields = {}
            if newv ~= nil then
                newv_fields = newv["fields"]
            end
            local _a, _r, _c =
                diff_schema_fields(oldv_fields, newv_fields, sub_prefix .. ".")
            added = in_place_merge(_a, added)
            removed = in_place_merge(_r, removed)
            changed = in_place_merge(_c, changed)


        elseif newv == nil then
            table_insert(removed, { path = sub_prefix })
            print_log("removed: " .. sub_prefix)

        elseif not deep_eq(oldv, newv) then
            table_insert(changed, { path = sub_prefix })
            print_log("changed: " .. sub_prefix)
        end
    end

    for _, item in pairs(new_fields) do
        local newk, newv = next(item)
        local oldv = find_field(old_fields, newk)
        local sub_prefix = prefix .. newk
        local is_nested_schema = type(newv) == "table"
            and newv["fields"] ~= nil
            and newv["type"] == "record"

        if is_nested_schema then
            local oldv_fields = {}
            local newv_fields = newv["fields"]
            if oldv ~= nil then
                oldv_fields = oldv["fields"]
            end

            local _a, _r, _c =
                diff_schema_fields(oldv_fields, newv_fields, sub_prefix .. ".")
            added = in_place_merge(_a, added)
            removed = in_place_merge(_r, removed)
            changed = in_place_merge(_c, changed)

        elseif oldv == nil then
            table_insert(added, { path = sub_prefix })
            print_log("added: " .. sub_prefix)
        end
    end

    return added, removed, changed
end


local function diff_schema(table_old, table_new)

    local old_fields = find_field(table_old.fields, "config").fields
    local new_fields = find_field(table_new.fields, "config").fields

    local added, removed, changed =
        diff_schema_fields(old_fields, new_fields, "")
    return {
        added = added,
        removed = removed,
        changed = changed,
    }
end


local function entry()
    -- read schema_old and  schema_new from args
    if #arg ~= 2 then
        print(USAGE)
        os.exit(1)
    end

    local schema_old_filename = arg[1]
    local schema_new_filename = arg[2]


    -- load schema_old and schema_new
    local schema_old = dofile(schema_old_filename)
    local schema_new = dofile(schema_new_filename)

    local result = diff_schema(schema_old, schema_new)
    print(cjson_encode({
        added = result.added,
        removed = result.removed,
        changed = result.changed,
    }))
end

if arg then
    entry()
end