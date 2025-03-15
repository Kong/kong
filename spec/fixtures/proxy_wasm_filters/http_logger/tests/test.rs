use std::time::Duration;
use proxy_wasm_test_framework::{FilterTester, LogLevel};

#[test]
fn test_http_logger_on_log() {
    let mut tester = FilterTester::default();
    
    // Configure the filter
    tester.set_root_context_configuration(r#"{
        "http_endpoint": "http://example.com/logs",
        "method": "POST",
        "content_type": "application/json",
        "timeout": 10000,
        "keepalive": 60000
    }"#);
    
    // Set up request
    tester.send_http_request(
        vec![
            (":method", "GET"),
            (":path", "/test"),
            (":authority", "example.com"),
            ("user-agent", "test-agent"),
        ],
        None,
    );
    
    // Set up response
    tester.set_http_response(
        vec![
            (":status", "200"),
            ("content-type", "application/json"),
        ],
        None,
    );
    
    // Verify logs
    tester.expect_log(LogLevel::Info, |log| log.contains("[http-logger]"));
    tester.expect_log(LogLevel::Info, |log| log.contains("\"method\":\"GET\""));
    tester.expect_log(LogLevel::Info, |log| log.contains("\"status\":\"200\""));
}

#[test]
fn test_http_logger_with_headers() {
    let mut tester = FilterTester::default();
    
    // Configure the filter
    tester.set_root_context_configuration(r#"{
        "http_endpoint": "http://example.com/logs",
        "method": "POST",
        "content_type": "application/json",
        "timeout": 10000,
        "keepalive": 60000,
        "headers": {
            "X-Custom-Header": "test-value"
        }
    }"#);
    
    // Set up request with custom headers
    tester.send_http_request(
        vec![
            (":method", "POST"),
            (":path", "/api/data"),
            (":authority", "example.com"),
            ("user-agent", "test-agent"),
            ("content-type", "application/json"),
            ("x-request-id", "12345"),
        ],
        Some(b"{\"test\":\"data\"}"),
    );
    
    // Set up response with custom headers
    tester.set_http_response(
        vec![
            (":status", "201"),
            ("content-type", "application/json"),
            ("x-response-id", "67890"),
        ],
        Some(b"{\"result\":\"success\"}"),
    );
    
    // Verify logs contain all headers
    tester.expect_log(LogLevel::Info, |log| log.contains("[http-logger]"));
    tester.expect_log(LogLevel::Info, |log| log.contains("\"method\":\"POST\""));
    tester.expect_log(LogLevel::Info, |log| log.contains("\"status\":\"201\""));
    tester.expect_log(LogLevel::Info, |log| log.contains("\"x-request-id\":\"12345\""));
    tester.expect_log(LogLevel::Info, |log| log.contains("\"x-response-id\":\"67890\""));
}
