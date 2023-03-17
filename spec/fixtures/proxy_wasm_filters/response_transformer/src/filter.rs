mod types;

use proxy_wasm::traits::{Context, RootContext, HttpContext};
use proxy_wasm::types::{Action, LogLevel, ContextType};
use crate::types::*;
use serde_json;
use log::*;

proxy_wasm::main! {{
   proxy_wasm::set_log_level(LogLevel::Info);
   proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> {
       Box::new(ResponseTransformerContext { config: Config::default() } )
   });
}}


struct ResponseTransformerContext {
    config: Config,
}

impl ResponseTransformerContext {
}

impl RootContext for ResponseTransformerContext {
    fn on_configure(&mut self, _: usize) -> bool {
        let bytes = self.get_plugin_configuration().unwrap();
        if let Ok(config) = serde_json::from_slice(bytes.as_slice()) {
            self.config = config;
            true
        } else {
            false
        }
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(ResponseTransformerContext{
            config: self.config.clone(),
        }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

impl Context for ResponseTransformerContext {
    fn on_done(&mut self) -> bool {
        true
    }
}

impl HttpContext for ResponseTransformerContext {
    fn on_http_response_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        self.config.remove.headers.iter().for_each(|name| {
            info!("[response-transformer] removing header: {}", name);
            self.set_http_response_header(&name, None);
        });

        self.config.rename.headers.iter().for_each(|KeyValuePair(from, to)| {
            info!("[response-transformer] renaming header {} => {}", from, to);
            let value = self.get_http_response_header(&from);
            self.set_http_response_header(&from, None);
            self.set_http_response_header(&to, value.as_deref());
        });

        self.config.replace.headers.iter().for_each(|KeyValuePair(name, value)| {
            if self.get_http_response_header(&name).is_some() {
                info!("[response-transformer] updating header {} value to {}", name, value);
                self.set_http_response_header(&name, Some(&value));
            }
        });

        self.config.add.headers.iter().for_each(|KeyValuePair(name, value)| {
            if self.get_http_response_header(&name).is_none() {
                info!("[response-transformer] adding header {} => {}", name, value);
                self.set_http_response_header(&name, Some(&value));
            }
        });

        self.config.append.headers.iter().for_each(|KeyValuePair(name, value)| {
            info!("[response-transformer] appending header {} => {}", name, value);
            self.add_http_response_header(&name, &value);
        });


        Action::Continue
    }
}
