return [[
# ------------------------------------------------------------------------------
# This is an example file to get you started with using
# declarative configuration in Kong.
# ------------------------------------------------------------------------------

# Metadata fields start with an underscore (_)
# Fields that do not start with an underscore represent Kong entities and attributes

# _format_version is mandatory,
# it specifies the minimum version of Kong that supports the format

_format_version: "3.0"

# _transform is optional, defaulting to true.
# It specifies whether schema transformations should be applied when importing this file
# as a rule of thumb, leave this setting to true if you are importing credentials
# with plain passwords, which need to be encrypted/hashed before storing on the database.
# On the other hand, if you are reimporting a database with passwords already encrypted/hashed,
# set it to false.

_transform: true

# Each Kong entity (core entity or custom entity introduced by a plugin)
# can be listed in the top-level as an array of objects:

# services:
# - name: example-service
#   url: http://example.com
#   # Entities can store tags as metadata
#   tags:
#   - example
#   # Entities that have a foreign-key relationship can be nested:
#   routes:
#   - name: example-route
#     paths:
#     - /
#   plugins:
#   - name: key-auth
# - name: another-service
#   url: https://example.org

# routes:
# - name: another-route
#   # Relationships can also be specified between top-level entities,
#   # either by name or by id
#   service: example-service
#   hosts: ["hello.com"]

# consumers:
# - username: example-user
#   # Custom entities from plugin can also be specified
#   # If they specify a foreign-key relationshp, they can also be nested
#   keyauth_credentials:
#   - key: my-key
#   plugins:
#   - name: rate-limiting
#     _comment: "these are default rate-limits for user example-user"
#     config:
#       policy: local
#       second: 5
#       hour: 10000

# When an entity has multiple foreign-key relationships
# (e.g. a plugin matching on both consumer and service)
# it must be specified as a top-level entity, and not through
# nesting.

# plugins:
# - name: rate-limiting
#   consumer: example-user
#   service: another-service
#   _comment: "example-user is extra limited when using another-service"
#   config:
#     hour: 2
#   # tags are for your organization only and have no meaning for Kong:
#   tags:
#   - extra_limits
#   - my_tag
]]
