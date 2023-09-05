#include <curl/curl.h>

#include <cassert>
#include <string>

// Use (void) to silent unused warnings.
#define assertm(exp, msg) assert(((void)msg, exp))

int main(int argc, char* argv[])
{
    curl_version_info_data* data = curl_version_info(CURLVERSION_NOW);

    assertm(std::string(data->version) == std::string("8.2.1"), "The version of curl does not match the expected version");
    assertm(std::string(data->ssl_version) == std::string("OpenSSL/3.1.2"), "The version of openssl does not match the expected version");
    assertm(std::string(data->nghttp2_version) == std::string("nghttp2/1.55.1"), "The version of nghttp2 does not match the expected version");

    return 0;
}
