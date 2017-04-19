return {
    no_consumer = true,
    fields = {
        name_limits_element = { required = false, type = "number", default = 0 },
        name_limits_attribute = { required = false, type = "number", default = 0 },
        name_limits_namespace_prefix = { required = false, type = "number", default = 0 },
        name_limits_processing_instruction_target = { required = false, type = "number", default = 0 },
        structure_limits_node_depth = { required = false, type = "number", default = 0 },
        structure_limits_attribute_count_per_element = { required = false, type = "number", default = 0 },
        structure_limits_namespace_count_per_element = { required = false, type = "number", default = 0 },
        structure_limits_child_count = { required = false, type = "number", default = 0 },
        value_limits_text = { required = false, type = "number", default = 0 },
        value_limits_attribute = { required = false, type = "number", default = 0 },
        value_limits_namespace_uri = { required = false, type = "number", default = 0 },
        value_limits_comment = { required = false, type = "number", default = 0 },
        value_limits_processing_instruction_data = { required = false, type = "number", default = 0 },
    }
}
