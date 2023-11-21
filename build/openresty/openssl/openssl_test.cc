#include <openssl/sha.h>

#include <cassert>
#include <iomanip>
#include <sstream>
#include <string>

// Use (void) to silent unused warnings.
#define assertm(exp, msg) assert(((void)msg, exp))

// From https://stackoverflow.com/a/2262447/7768383
bool simpleSHA256(const void* input, unsigned long length, unsigned char* md)
{
    SHA256_CTX context;
    if (!SHA256_Init(&context))
        return false;

    if (!SHA256_Update(&context, (unsigned char*)input, length))
        return false;

    if (!SHA256_Final(md, &context))
        return false;

    return true;
}

// Convert an byte array into a string
std::string fromByteArray(const unsigned char* data, unsigned long length)
{
    std::stringstream shastr;
    shastr << std::hex << std::setfill('0');
    for (unsigned long i = 0; i < length; ++i)
    {
        shastr << std::setw(2) << static_cast<int>(data[i]);
    }

    return shastr.str();
}

std::string MESSAGE = "hello world";
std::string MESSAGE_HASH = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9";

int main(int argc, char* argv[])
{
    unsigned char md[SHA256_DIGEST_LENGTH] = {};

    assertm(simpleSHA256(static_cast<const void*>(MESSAGE.data()), MESSAGE.size(), md), "Failed to generate hash");
    std::string hash = fromByteArray(md, SHA256_DIGEST_LENGTH);

    assertm(hash == MESSAGE_HASH, "Unexpected message hash");

    return 0;
}
