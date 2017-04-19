describe("XML Threat Protection Validator Test Suite", function()

    local xtp
    local status
    local message

    setup(function()
        xtp = require "kong.plugins.xml-threat-protection.xml_validator"
        status = nil
        message = nil
    end)

    teardown(function()
        xtp = nil
        status = nil
        message = nil
    end)

    it("Test with valid json", function()
        local xml = "<book category=\"WEB\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid json", function()
        local xml = "<book category=\"WEB\"><ti"
        status, message = xtp.execute(xml,
            10, --name_limits_element
            10, --name_limits_attribute,
            10, --name_limits_namespace_prefix,
            10, --name_limits_processing_instruction_target,
            10, --structure_limits_node_depth,
            10, --structure_limits_attribute_count_per_element,
            10, --structure_limits_namespace_count_per_element,
            10, --structure_limits_child_count,
            10, --value_limits_text,
            10, --value_limits_attribute,
            10, --value_limits_namespace_uri,
            10, --value_limits_comment,
            10) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with name limits element ignored", function()
        local xml = "<book category=\"WEB\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            0, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid name limits element", function()
        local xml = "<book category=\"WEB\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            5, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[ElemNameExceeded]: Element name length exceeded (author), max 5 allowed, found 6.")
    end)

    it("Test with name limits attribute ignored", function()
        local xml = "<book category=\"WEB\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            0, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid name limits attribute", function()
        local xml = "<book category=\"WEB\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            5, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[AttrNameExceeded]: Attribute name length exceeded (category), max 5 allowed, found 8.")
    end)

    it("Test with name limits namespace prefix ignored", function()
        local xml = "<ns1:myelem xmlns:ns1=\"http://ns1.com\"/>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            0, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid name limits namespace prefix", function()
        local xml = "<ns1:myelem xmlns:namespace1=\"http://ns1.com\"/>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            5, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[NSPrefixExceeded]: Namespace prefix length exceeded (xmlns:namespace1), max 5 allowed, found 10.")
    end)

    it("Test with name limits processing instruction target ignored", function()
        local xml = "<?xml-stylesheet type=\"text/xsl\" href=\"/style.xsl\"?>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            0, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid name limits processing instruction target", function()
        local xml = "<?xml-stylesheet type=\"text/xsl\" href=\"/style.xsl\"?>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            5, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[PITargetExceeded]: Processing Instruction target length exceeded (xml-stylesheet), max 5 allowed, found 14.")
    end)

    it("Test with structure limits node depth ignored", function()
        local xml = "<books><book><title>Learning XML</title><type><value>text</value></type></book></books>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            0, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with structure limits node depth element", function()
        local xml = "<books><book><title>Learning XML</title><type><value>text</value></type></book></books>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            2, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[NodeDepthExceeded]: Node depth exceeded, max 2 allowed, found 3.")
    end)

    it("Test with structure limits attribute count per element ignored", function()
        local xml = "<book category=\"WEB\" cat2=\"WEB2\" cat3=\"WEB3\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            0, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid structure limits attribute count per element", function()
        local xml = "<book category=\"WEB\" cat2=\"WEB2\" cat3=\"WEB3\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            2, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[AttrCountExceeded]: Attribute count exceed, max 2 allowed, found 3.")
    end)

    it("Test with structure limits namespace count per element ignored", function()
        local xml = "<e1 attr1=\"val1\" attr2=\"val2\"><e2 xmlns=\"http://apigee.com\" xmlns:yahoo=\"http://yahoo.com\" one=\"1\" yahoo:two=\"2\"/></e1>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            0, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid structure limits namespace count per element", function()
        local xml = "<e1 attr1=\"val1\" attr2=\"val2\"><e2 xmlns=\"http://apigee.com\" xmlns:yahoo=\"http://yahoo.com\" one=\"1\" yahoo:two=\"2\"/></e1>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            1, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[NSCountExceeded]: Namespace count exceeded, max 1 allowed, found 2.")
    end)

    it("Test with structure limits child count ignored", function()
        local xml = "<book category=\"WEB\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            0, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid structure limits child count", function()
        local xml = "<book category=\"WEB\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            2, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[ChildCountExceeded]: Children count exceeded, max 2 allowed, found 3.")
    end)

    it("Test with value limits text ignored", function()
        local xml = "<book category=\"WEB\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            0, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid value limits text", function()
        local xml = "<book category=\"WEB\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            5, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[TextExceeded]: Text length exceeded (Learning XML), max 5 allowed, found 12.")
    end)

    it("Test with value limits attribute ignored", function()
        local xml = "<book category=\"WEB\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            0, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid value limits attribute", function()
        local xml = "<book category=\"WEBlong\"><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            5, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[AttrValueExceeded]: Attribute value length exceeded (WEBlong), max 5 allowed, found 7.")
    end)

    it("Test with value limits namespace uri ignored", function()
        local xml = "<ns1:myelem xmlns:ns1=\"http://ns1.com\"/>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            0, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid value limits namespace uri", function()
        local xml = "<ns1:myelem xmlns:ns1=\"http://ns1.com\"/>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            5, --value_limits_namespace_uri,
            50, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[NSURIExceeded]: Namespace uri length exceeded (http://ns1.com), max 5 allowed, found 14.")
    end)

    it("Test with value limits comment ignored", function()
        local xml = "<book category=\"WEB\"><!-- This is a comment --><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            0, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid value limits comment", function()
        local xml = "<book category=\"WEB\"><!-- This is a comment --><title>Learning XML</title><author>Erik T. Ray</author><year>2003</year></book>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            5, --value_limits_comment,
            50) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[CommentExceeded]: Comment length exceeded (This is a comment), max 5 allowed, found 17.")
    end)

    it("Test with value limits processing instruction data ignored", function()
        local xml = "<?xml-stylesheet type=\"text/xsl\" href=\"/style.xsl\"?>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            0) --value_limits_processing_instruction_data)

        assert.equal(status, true)
        assert.equal(message, "")
    end)

    it("Test with invalid value limits processing instruction data", function()
        local xml = "<?xml-stylesheet type=\"text/xsl\" href=\"/style.xsl\"?>"
        status, message = xtp.execute(xml,
            50, --name_limits_element
            50, --name_limits_attribute,
            50, --name_limits_namespace_prefix,
            50, --name_limits_processing_instruction_target,
            50, --structure_limits_node_depth,
            50, --structure_limits_attribute_count_per_element,
            50, --structure_limits_namespace_count_per_element,
            50, --structure_limits_child_count,
            50, --value_limits_text,
            50, --value_limits_attribute,
            50, --value_limits_namespace_uri,
            50, --value_limits_comment,
            5) --value_limits_processing_instruction_data)

        assert.equal(status, false)
        assert.equal(message, "XMLThreatProtection[PIDataExceeded]: Processing Instruction data length exceeded (type=\"text/xsl\"), max 5 allowed, found 15.")
    end)
end)
