local string = require "string"
require("LuaXML")

local XmlValidator = {}

-------------
-- Globals --
-------------
local nl_element
local nl_attribute
local nl_ns_prefix
local st_lnd
local st_lacpe
local st_lncpe
local st_lcc
local vl_text
local vl_attrib
local vl_ns_uri
local depth

----------------------
-- Utility function --
----------------------

function string.starts(String, Start)
    return string.sub(String, 1, string.len(Start)) == Start
end

function string.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

--------------------------
-- Validation functions --
--------------------------

local function validatePit(pit, nl_pit, vl_pid)
    local spacePos

    if nl_pit > 0 then -- Validate the processing instruction target length
        spacePos = string.find(pit, " ")
        if spacePos then
            local tag = string.sub(pit, 0, spacePos - 1)
            if #tag > nl_pit then
                return false, "XMLThreatProtection[PITargetExceeded]: Processing Instruction target length exceeded (" .. tag .. "), max " .. nl_pit .. " allowed, found " .. #tag .. "."
            end
        end
    end

    if vl_pid > 0 then
        while spacePos do
            local quotePos = string.find(pit, '"', spacePos) -- find begin quote
            quotePos = string.find(pit, '"', quotePos + 1) -- find trailing quote
            if quotePos then
                local pid = string.trim(string.sub(pit, spacePos + 1, quotePos))
                if #pid > vl_pid then
                    return false, "XMLThreatProtection[PIDataExceeded]: Processing Instruction data length exceeded (" .. pid .. "), max " .. vl_pid .. " allowed, found " .. #pid .. "."
                end
            end

            spacePos = string.find(pit, " ", quotePos) -- find next space
        end
    end

    return true, ""
end

local function validateComments(body, vl_comment)

    local commentPos

    if vl_comment > 0 then
        commentPos = string.find(body, "<!--")
        while commentPos do
            local commentEnd = string.find(body, "-->", commentPos)
            local comment = string.trim(string.sub(body, commentPos + 4, commentEnd - 2))
            if #comment > vl_comment then
                return false, "XMLThreatProtection[CommentExceeded]: Comment length exceeded (" .. comment .. "), max " .. vl_comment .. " allowed, found " .. #comment .. "."
            end

            commentPos = string.find(body, "<!--", commentEnd)
        end
    end

    return true, ""
end

local function validateNamespace(ns, value)
    if nl_ns_prefix > 0 then

        -- Check if a namespace prefix is defined
        local pos = string.find(ns, ":")
        if pos then
            local prefix = string.sub(ns, pos + 1) -- also skip the ':'
            if #prefix > nl_ns_prefix then
                return false, "XMLThreatProtection[NSPrefixExceeded]: Namespace prefix length exceeded (" .. ns .. "), max " .. nl_ns_prefix .. " allowed, found " .. #prefix .. "."
            end
        end
    end

    if vl_ns_uri > 0 then
        if #value > vl_ns_uri then
            return false, "XMLThreatProtection[NSURIExceeded]: Namespace uri length exceeded (" .. value .. "), max " .. vl_ns_uri .. " allowed, found " .. #value .. "."
        end
    end

    return true, ""
end

local function validateAttribute(attrib, value)
    if nl_attribute > 0 then
        if #attrib > nl_attribute then
            return false, "XMLThreatProtection[AttrNameExceeded]: Attribute name length exceeded (" .. attrib .. "), max " .. nl_attribute .. " allowed, found " .. #attrib .. "."
        end
    end

    if vl_attrib > 0 then
        if #value > vl_attrib then
            return false, "XMLThreatProtection[AttrValueExceeded]: Attribute value length exceeded (" .. value .. "), max " .. vl_attrib .. " allowed, found " .. #value .. "."
        end
    end

    return true, ""
end

local function validateElement(element)
    if nl_element > 0 then
        if #element > nl_element then
            return false, "XMLThreatProtection[ElemNameExceeded]: Element name length exceeded (" .. element .. "), max " .. nl_element .. " allowed, found " .. #element .. "."
        end
    end

    return true, ""
end

local function validateXml(value)
    if type(value) == "table" then

        -- Validate the child count
        if st_lcc > 0 then
            if #value > st_lcc then
                return false, "XMLThreatProtection[ChildCountExceeded]: Children count exceeded, max " .. st_lcc .. " allowed, found " .. #value .. "."
            end
        end

        local namespaceCount = 0
        local attributeCount = 0
        local children = 0

        for k,v in pairs(value) do
            if k == 0 then -- TAG
                local result, message = validateElement(v)
                if result == false then
                    return result, message
                end
            elseif k == 1 and type(v) == "table" then
                depth = depth + 1
                if st_lnd > 0 then
                    if depth > st_lnd then
                        return false, "XMLThreatProtection[NodeDepthExceeded]: Node depth exceeded, max " .. st_lnd .. " allowed, found " .. depth .. "."
                    end
                end
            elseif type(k) == "string" then
                if string.starts(k, "xmlns") then
                    namespaceCount = namespaceCount + 1
                    if st_lncpe > 0 then  -- Validate the namespace count per element
                        if namespaceCount > st_lncpe then
                            return false, "XMLThreatProtection[NSCountExceeded]: Namespace count exceeded, max " .. st_lncpe .. " allowed, found " .. namespaceCount .. "."
                        end
                    end

                    local result, message = validateNamespace(k, value[k]) -- Validate the namespace name and value
                    if result == false then
                        return result, message
                    end
                else
                    attributeCount = attributeCount + 1
                    if st_lacpe > 0 then   -- Validate the attribute count per element
                        if attributeCount > st_lacpe then
                            return false, "XMLThreatProtection[AttrCountExceeded]: Attribute count exceed, max " .. st_lacpe .. " allowed, found " .. attributeCount .. "."
                        end
                    end

                    -- Validate the attribute name and value
                    local result, message = validateAttribute(k, value[k])
                    if result == false then
                        return result, message
                    end
                end
            else
                children = children + 1
                if st_lcc > 0 then
                    if children > st_lcc then
                        return false, "XMLThreatProtection[ChildCountExceeded]: Children count exceeded, max " .. st_lcc .. " allowed, found " .. children .. "."
                    end
                end

                -- recursively repeat the same procedure
                local result, message = validateXml(v)
                if result == false then
                    return result, message
                end
            end
        end
    else
        if vl_text > 0 then
            if #value > vl_text then
                return false, "XMLThreatProtection[TextExceeded]: Text length exceeded (" .. value .. "), max " .. vl_text .. " allowed, found " .. #value .. "."
            end
        end
    end

    return true, ""
end
------------------------------
-- Validator implementation --
------------------------------

function XmlValidator.execute(body,
    name_limits_element,
    name_limits_attribute,
    name_limits_namespace_prefix,
    name_limits_processing_instruction_target,
    structure_limits_node_depth,
    structure_limits_attribute_count_per_element,
    structure_limits_namespace_count_per_element,
    structure_limits_child_count,
    value_limits_text,
    value_limits_attribute,
    value_limits_namespace_uri,
    value_limits_comment,
    value_limits_processing_instruction_data)

    nl_element = name_limits_element
    nl_attribute = name_limits_attribute
    nl_ns_prefix = name_limits_namespace_prefix

    st_lnd = structure_limits_node_depth
    st_lacpe = structure_limits_attribute_count_per_element
    st_lncpe = structure_limits_namespace_count_per_element
    st_lcc = structure_limits_child_count

    vl_text = value_limits_text
    vl_attrib = value_limits_attribute
    vl_ns_uri = value_limits_namespace_uri

    -- Validate the processing instruction target and data
    if string.starts(body, "<?") then
        local position = string.find(body, "?>")
        local pit = string.trim(string.sub(body, 3, position - 1))

        local result, message = validatePit(pit, name_limits_processing_instruction_target, value_limits_processing_instruction_data)
        if result == false then
            return result, message
        end
    end

    -- Validate the xml comments
    local result, message = validateComments(body, value_limits_comment)
    if result == false then
        return result, message
    end

    -- Parse
    local parsedXml = xml.eval(body)
    if not parsedXml then
        return true, ""
    end

    depth = 0
    return validateXml(parsedXml)
end

return XmlValidator
