"""A centralized module defining all repositories required for third party examples of rules_foreign_cc"""

load("//build/ee/libexpat:repositories.bzl", "libexpat_repositories")
load("//build/ee/libxml2:repositories.bzl", "libxml2_repositories")
load("//build/ee/libxslt:repositories.bzl", "libxslt_repositories")
load("//build/ee/gmp:repositories.bzl", "gmp_repositories")
load("//build/ee/nettle:repositories.bzl", "nettle_repositories")
load("//build/ee/jq:repositories.bzl", "jq_repositories")
load("//build/ee/passwdqc:repositories.bzl", "passwdqc_repositories")
load("//build/ee/boringssl_fips:repositories.bzl", "boringssl_fips_repositories")
load("//build/ee/kong-licensing:repositories.bzl", "kong_licensing_repositories")

# buildifier: disable=unnamed-macro
def ee_repositories():
    """Load all repositories needed for the targets of rules_foreign_cc_examples_third_party"""
    libexpat_repositories()
    libxml2_repositories()
    libxslt_repositories()
    gmp_repositories()
    nettle_repositories()
    jq_repositories()
    passwdqc_repositories()
    kong_licensing_repositories()

    boringssl_fips_repositories()
