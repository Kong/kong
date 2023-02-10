mod routines;
mod test_http;
mod types;

use crate::routines::*;
use crate::test_http::*;
use crate::types::*;
use http::StatusCode;
use log::*;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::str::FromStr;
use std::time::Duration;

proxy_wasm::main! {{
   proxy_wasm::set_log_level(LogLevel::Info);
   proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> {
       Box::new(TestRoot { config: None })
   });
}}

struct TestRoot {
    config: Option<TestConfig>,
}

impl Context for TestRoot {}

impl RootContext for TestRoot {
    fn on_vm_start(&mut self, conf_size: usize) -> bool {
        info!("[proxy-wasm root] on_vm_start (conf_size: {})", conf_size);
        true
    }

    fn on_configure(&mut self, conf_size: usize) -> bool {
        info!("[proxy-wasm root] on_configure (conf_size: {})", conf_size);

        if let Some(bytes) = self.get_plugin_configuration() {
            let config: &str = std::str::from_utf8(&bytes).unwrap();
            self.config = TestConfig::from_str(config).ok();

            if let Some(every) = self.config.as_ref().unwrap().map.get("tick_every") {
                let ms = every.parse().expect("bad tick_every");
                info!("starting on_tick every {}ms", ms);

                self.set_tick_period(Duration::from_millis(ms));
            }
        }

        true
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, context_id: u32) -> Option<Box<dyn HttpContext>> {
        info!(
            "[proxy-wasm root] create_http_context (id: #{})",
            context_id
        );

        Some(Box::new(TestHttp { config: None }))
    }

    fn on_tick(&mut self) {
        info!("[proxy-wasm root] on_tick");
    }
}

impl Context for TestHttp {
    fn on_http_call_response(
        &mut self,
        token_id: u32,
        nheaders: usize,
        body_size: usize,
        _ntrailers: usize,
    ) {
        const HEADER_NAME: &str = "X-PW-Dispatch-Echo";

        info!(
            "[proxy-wasm http] on_http_call_response (token_id: {}, headers: {}, body_bytes: {})",
            token_id, nheaders, body_size
        );

        if let Some(bytes) = self.get_http_call_response_body(0, usize::MAX) {
            let body = String::from_utf8(bytes).unwrap();
            info!("[proxy-wasm] http_call_response body: {:?}", body);

            if let Some(v) = self.get_http_request_header(HEADER_NAME) {
                match v.as_str() {
                    "on" | "true" | "T" | "1" => {
                        self.send_plain_response(StatusCode::OK, Some(body.trim()))
                    }
                    _ => {}
                }
            }
        }

        self.resume_http_request()
    }
}

impl HttpContext for TestHttp {
    fn on_http_request_headers(&mut self, nheaders: usize, eof: bool) -> Action {
        info!(
            "[proxy-wasm http] on_request_headers ({} headers, eof: {})",
            nheaders, eof
        );

        self.run_tests(TestPhase::RequestHeaders)
    }

    fn on_http_request_body(&mut self, size: usize, eof: bool) -> Action {
        info!(
            "[proxy-wasm http] on_request_body ({} bytes, eof: {})",
            size, eof
        );

        self.run_tests(TestPhase::RequestBody)
    }

    fn on_http_response_headers(&mut self, nheaders: usize, eof: bool) -> Action {
        info!(
            "[proxy-wasm http] on_response_headers ({} headers, eof: {})",
            nheaders, eof
        );

        self.run_tests(TestPhase::ResponseHeaders)
    }

    fn on_http_response_body(&mut self, size: usize, eof: bool) -> Action {
        info!(
            "[proxy-wasm http] on_response_body ({} bytes, eof {})",
            size, eof
        );

        self.run_tests(TestPhase::ResponseBody)
    }

    fn on_log(&mut self) {
        info!("[proxy-wasm http] on_log");
        self.run_tests(TestPhase::Log);
    }
}
