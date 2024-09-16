use std::collections::HashMap;
use std::cell::RefCell;
use proxy_wasm::hostcalls::{define_metric, increment_metric, record_metric};
use proxy_wasm::types::{MetricType, Status};

thread_local! {
    static METRICS: Metrics = Metrics::new();
}

struct Metrics {
    metrics: RefCell<HashMap<String, u32>>,
}

impl Metrics {
    fn new() -> Metrics {
        Metrics {
            metrics: RefCell::new(HashMap::new()),
        }
    }

    fn get_metric_id(&self, metric_type: MetricType, name: &str) -> Result<u32, Status> {
        let mut map = self.metrics.borrow_mut();

        match map.get(name) {
            Some(m_id) => Ok(*m_id),
            None => {
                match define_metric(metric_type, name) {
                    Ok(m_id) => {
                        map.insert(name.to_string(), m_id);

                        Ok(m_id)
                    },
                    Err(msg) => Err(msg)
                }
            }
        }
    }
}

pub fn define(m_type: MetricType, name: &str) -> Result<u32, Status> {
    METRICS.with(|metrics| metrics.get_metric_id(m_type, name))
}

pub fn increment_counter(name: &str) -> Result<(), Status> {
    increment_metric(define(MetricType::Counter, name).unwrap(), 1)
}

pub fn record_gauge(name: &str, value: u64) -> Result<(), Status> {
    record_metric(define(MetricType::Gauge, name).unwrap(), value)
}

pub fn record_histogram(name: &str, value: u64) -> Result<(), Status> {
    record_metric(define(MetricType::Histogram, name).unwrap(), value)
}
