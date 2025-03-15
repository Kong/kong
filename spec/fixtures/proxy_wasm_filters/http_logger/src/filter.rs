mod types;

use proxy_wasm::traits::{Context, RootContext, HttpContext};
use proxy_wasm::types::{Action, LogLevel, ContextType};
use crate::types::*;
use serde_json;
use log::*;

proxy_wasm::main! {{
   proxy_wasm::set_log_level(LogLevel::Info);
   proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> {
       Box::new(HttpLoggerContext { config: Config::default() } )
   });
}}

struct HttpLoggerContext {
    config: Config,
}

impl RootContext for HttpLoggerContext {
    fn on_configure(&mut self, _: usize) -> bool {
        let bytes = self.get_plugin_configuration().unwrap();
        match serde_json::from_slice::<Config>(bytes.as_slice()) {
            Ok(config) => {
                self.config = config;
                true
            },
            Err(e) => {
                error!("failed parsing filter config: {}", e);
                false
            }
        }
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpLoggerContext{
            config: self.config.clone(),
        }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

impl Context for HttpLoggerContext {
    fn on_done(&mut self) -> bool {
        true
    }
}

impl HttpContext for HttpLoggerContext {
    fn on_http_response_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        Action::Continue
    }

    fn on_log(&mut self) -> Action {
        // Collect request information
        let method = self.get_http_request_header(":method")
            .unwrap_or_else(|| "".to_string());
        let path = self.get_http_request_header(":path")
            .unwrap_or_else(|| "".to_string());
        let host = self.get_http_request_header(":authority")
            .unwrap_or_else(|| "".to_string());
        
        // Collect response information
        let status = self.get_http_response_header(":status")
            .unwrap_or_else(|| "".to_string());
        
        // Create log entry
        let mut log_entry = serde_json::json!({
            "request": {
                "method": method,
                "url": path,
                "host": host,
                "headers": {}
            },
            "response": {
                "status": status,
                "headers": {}
            },
            "client_ip": self.get_property(vec!["source", "address"])
                .map(|addr| String::from_utf8_lossy(&addr).to_string())
                .unwrap_or_else(|| "".to_string()),
            "started_at": self.get_current_time()
        });
        
        // Add request headers
        let req_headers = log_entry["request"]["headers"].as_object_mut().unwrap();
        for (name, value) in self.get_http_request_headers() {
            if !name.starts_with(':') {
                req_headers.insert(name, serde_json::Value::String(value));
            }
        }
        
        // Add response headers
        let resp_headers = log_entry["response"]["headers"].as_object_mut().unwrap();
        for (name, value) in self.get_http_response_headers() {
            if !name.starts_with(':') {
                resp_headers.insert(name, serde_json::Value::String(value));
            }
        }
        
        // Log the entry
        info!("[http-logger] {}", serde_json::to_string(&log_entry).unwrap());
        
        // TODO: Send log entry to HTTP endpoint
        // This would require implementing HTTP dispatch functionality
        
        Action::Continue
    }
}
