local schemas = require "kong.dao.schemas_validation"
local validate_entity = schemas.validate_entity

local schema = require "kong.plugins.xml-threat-protection.schema"

describe("XML Threat Protection schema", function()
    it("should work when no configuration has been set", function()
        local config = {}
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.name_limits_element == 0)
        assert.is_true(config.name_limits_attribute == 0)
        assert.is_true(config.name_limits_namespace_prefix == 0)
        assert.is_true(config.name_limits_processing_instruction_target == 0)
        assert.is_true(config.structure_limits_node_depth == 0)
        assert.is_true(config.structure_limits_attribute_count_per_element == 0)
        assert.is_true(config.structure_limits_namespace_count_per_element == 0)
        assert.is_true(config.structure_limits_child_count == 0)
        assert.is_true(config.value_limits_text == 0)
        assert.is_true(config.value_limits_attribute == 0)
        assert.is_true(config.value_limits_namespace_uri == 0)
        assert.is_true(config.value_limits_comment == 0)
        assert.is_true(config.value_limits_processing_instruction_data == 0)
    end)

    it("should work when name limits element is not set", function()
        local config =
        {
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.name_limits_element == 0)
    end)

    it("should work when name limits attribute is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.name_limits_attribute == 0)
    end)

    it("should work when name limits namespace prefix is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.name_limits_namespace_prefix == 0)
    end)

    it("should work when name limits processing instruction target is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.name_limits_processing_instruction_target == 0)
    end)

    it("should work when structure limits node depth is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.structure_limits_node_depth == 0)
    end)

    it("should work when struture limits attribute count per element is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.structure_limits_attribute_count_per_element == 0)
    end)

    it("should work when structure limits namespace count per element is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.structure_limits_namespace_count_per_element == 0)
    end)

    it("should work when structure limits child count is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.structure_limits_child_count == 0)
    end)

    it("should work when value limits text is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.value_limits_text == 0)
    end)

    it("should work when value limits attribute is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.value_limits_attribute == 0)
    end)

    it("should work when value limits namespace uri is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_comment = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.value_limits_namespace_uri == 0)
    end)

    it("should work when value limits comment is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_processing_instruction_data = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.value_limits_comment == 0)
    end)

    it("should work when value limits processing instruction data is not set", function()
        local config =
        {
            name_limits_element = 10,
            name_limits_attribute = 10,
            name_limits_namespace_prefix = 10,
            name_limits_processing_instruction_target = 10,
            structure_limits_node_depth = 10,
            structure_limits_attribute_count_per_element = 10,
            structure_limits_namespace_count_per_element = 10,
            structure_limits_child_count = 10,
            value_limits_text = 10,
            value_limits_attribute = 10,
            value_limits_namespace_uri = 10,
            value_limits_comment = 10
        }
        local valid, err = validate_entity(config, schema)
        assert.truthy(valid)
        assert.falsy(err)
        assert.is_true(config.value_limits_processing_instruction_data == 0)
    end)
end)
