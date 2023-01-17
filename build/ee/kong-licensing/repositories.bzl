"""A module defining the third party dependency OpenResty"""

def kong_licensing_repositories():
    """Defines the libexpat repository"""

    native.new_local_repository(
        name = "kong-licensing",
        path = "distribution/kong-licensing/lib",
        build_file = "//build/ee/kong-licensing:BUILD.kong-licensing.bazel",
    )
