"""A centralized module defining all repositories required for third party examples of rules_foreign_cc"""

load("//build/ee/jq:repositories.bzl", "jq_repositories")
load("//build/ee/kong-licensing:repositories.bzl", "kong_licensing_repositories")
load("//build/ee/kong_gql:kong-gql_repositories.bzl", "kong_gql_repositories")
load("//build/ee/libxml2:repositories.bzl", "libxml2_repositories")
load("//build/ee/libxslt:repositories.bzl", "libxslt_repositories")
load("//build/ee/openssl_fips:repositories.bzl", "openssl_fips_repositories")
load("//build/ee/passwdqc:repositories.bzl", "passwdqc_repositories")
load("//build/ee/resty_openapi3_deserializer:resty_openapi3_deserializer_repositories.bzl", "resty_openapi3_deserializer_repositories")

# buildifier: disable=unnamed-macro
def ee_repositories():
    """Load all repositories needed for the targets of rules_foreign_cc_examples_third_party"""
    libxml2_repositories()
    libxslt_repositories()
    jq_repositories()
    passwdqc_repositories()
    kong_licensing_repositories()
    openssl_fips_repositories()
    resty_openapi3_deserializer_repositories()
    kong_gql_repositories()
