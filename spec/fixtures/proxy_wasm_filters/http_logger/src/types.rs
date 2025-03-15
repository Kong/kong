use serde::Deserialize;

#[derive(Deserialize, Default, Clone)]
#[serde(default)]
pub(crate) struct Config {
    pub(crate) http_endpoint: String,
    pub(crate) method: String,
    pub(crate) content_type: String,
    pub(crate) timeout: u32,
    pub(crate) keepalive: u32,
    pub(crate) headers: std::collections::HashMap<String, String>,
}
