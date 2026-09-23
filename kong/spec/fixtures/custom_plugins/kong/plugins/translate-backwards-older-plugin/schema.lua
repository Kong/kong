return {
  name = "translate-backwards-older-plugin",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { new_field = { type = "string", default = "new-value" } },
        },
        shorthand_fields = {
          { old_field = {
            type = "string",
            translate_backwards = { 'new_field' },
            deprecation = {
              message = "translate-backwards-older-plugin: config.old_field is deprecated, please use config.new_field instead",
              removal_in_version = "4.0", },
            func = function(value)
              return { new_field = value }
            end
          } },
        },
      },
    },
  },
}
