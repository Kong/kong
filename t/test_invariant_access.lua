#include <check.h>
#include <stdlib.h>
#include <string.h>
#include <curl/curl.h>

START_TEST(test_ldap_auth_rejects_unauthenticated)
{
    // Invariant: Protected endpoints reject unauthenticated requests
    const char *payloads[] = {
        "",  // Missing token
        "Bearer expired.jwt.token",  // Expired token
        "Bearer malformed",  // Malformed token
        "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",  // Valid JWT but invalid for LDAP
        "Basic invalid:credentials"  // Invalid basic auth
    };
    int num_payloads = sizeof(payloads) / sizeof(payloads[0]);

    CURL *curl;
    CURLcode res;
    long response_code;
    
    for (int i = 0; i < num_payloads; i++) {
        curl = curl_easy_init();
        if (curl) {
            struct curl_slist *headers = NULL;
            
            // Add Authorization header if payload is not empty
            if (strlen(payloads[i]) > 0) {
                char auth_header[256];
                snprintf(auth_header, sizeof(auth_header), "Authorization: %s", payloads[i]);
                headers = curl_slist_append(headers, auth_header);
            }
            
            curl_easy_setopt(curl, CURLOPT_URL, "http://localhost:8000/protected-endpoint");
            curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
            curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);  // HEAD request
            curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5L);
            
            res = curl_easy_perform(curl);
            
            if (res == CURLE_OK) {
                curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
                // Assert 401 Unauthorized or 403 Forbidden
                ck_assert_msg(response_code == 401 || response_code == 403,
                            "Payload '%s' returned %ld, expected 401 or 403",
                            payloads[i], response_code);
            }
            
            curl_slist_free_all(headers);
            curl_easy_cleanup(curl);
        }
    }
}
END_TEST

Suite *security_suite(void)
{
    Suite *s;
    TCase *tc_core;

    s = suite_create("Security");
    tc_core = tcase_create("Core");

    tcase_add_test(tc_core, test_ldap_auth_rejects_unauthenticated);
    suite_add_tcase(s, tc_core);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = security_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}