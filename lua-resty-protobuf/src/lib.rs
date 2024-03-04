mod ffi;

use prost::Message;
use rand::prelude::*;
use std::time;

use bytes::BytesMut;

use opentelemetry_proto::tonic::{
    common::v1::{any_value, AnyValue, InstrumentationScope, KeyValue},
    logs::v1::{LogRecord, LogsData, ResourceLogs, ScopeLogs, SeverityNumber},
    metrics::v1::{
        metric::Data, number_data_point::Value, Gauge, Metric, MetricsData, NumberDataPoint,
        ResourceMetrics, ScopeMetrics, Sum,
    },
    resource::v1::Resource,
    trace::v1::{ResourceSpans, ScopeSpans, Span, TracesData},
};

const DEFAULT_CONTEXT_CAPACITY: usize = 16;

fn _get_current_time_unix_nano() -> u64 {
    let now = time::SystemTime::now();
    let nano = now.duration_since(time::UNIX_EPOCH).unwrap().as_nanos();

    let nano_u64 = nano.try_into();
    if let Ok(nano_u64) = nano_u64 {
        nano_u64
    } else {
        // TODO: error handlingx
        panic!("Failed to convert time to u64");
    }
}

pub struct Traces {
    rng: ThreadRng,
    context: Vec<Span>,

    trace_id: [u8; 16],

    traces_data: TracesData,
    resource_spans: ResourceSpans,
    scope_spans: ScopeSpans,
}

impl Traces {
    pub fn new() -> Self {
        let mut rng = thread_rng();
        let mut trace_id = [0; 16];
        rng.fill_bytes(&mut trace_id);

        let mut scope_spans = ScopeSpans::default();
        scope_spans.spans.reserve(128);

        Traces {
            rng,
            context: Vec::with_capacity(DEFAULT_CONTEXT_CAPACITY),

            trace_id,

            traces_data: TracesData::default(),
            resource_spans: ResourceSpans::default(),
            scope_spans,
        }
    }

    pub fn get_serialized(mut self, buf: &mut BytesMut) {
        let mut resource = Resource::default();
        resource.attributes.push(KeyValue {
            key: "service.name".to_string(),
            value: Some(AnyValue {
                value: Some(any_value::Value::StringValue(
                    "kong-gateway-qiqi-demo".to_string(),
                )),
            }),
        });
        resource.attributes.push(KeyValue {
            key: "service".to_string(),
            value: Some(AnyValue {
                value: Some(any_value::Value::StringValue(
                    "kong-gateway-qiqi-demo".to_string(),
                )),
            }),
        });
        resource.attributes.push(KeyValue {
            key: "env".to_string(),
            value: Some(AnyValue {
                value: Some(any_value::Value::StringValue("dev".to_string())),
            }),
        });

        let mut instrumentation_scope = InstrumentationScope::default();
        instrumentation_scope.name = "kong-gateway-efficient-tracing-subsystem".to_string();
        self.scope_spans.scope = Some(instrumentation_scope);

        self.resource_spans.resource = Some(resource);
        self.resource_spans.scope_spans.push(self.scope_spans);
        self.traces_data.resource_spans.push(self.resource_spans);

        self.traces_data.encode(buf).unwrap();
    }

    pub fn enter_span(&mut self, name: &str) {
        let mut span = Span::default();
        span.trace_id = self.trace_id.to_vec();
        span.span_id = self._gen_span_id().to_vec();
        span.name = name.to_string();
        span.start_time_unix_nano = _get_current_time_unix_nano();

        if let Some(parent_span) = self.context.last() {
            span.parent_span_id = parent_span.span_id.clone();
        }

        self.context.push(span);
    }

    pub fn exit_span(&mut self) {
        debug_assert!(self.context.len() > 0, "No span to exit");

        let mut span = self.context.pop().unwrap();
        span.end_time_unix_nano = _get_current_time_unix_nano();

        self.scope_spans.spans.push(span);
    }

    pub fn add_string_attribute(&mut self, key: &str, value: &str) {
        debug_assert!(self.context.len() > 0, "No span to add attribute");

        let str_value = any_value::Value::StringValue(value.to_string());
        let any_value = AnyValue {
            value: Some(str_value),
        };

        let mut attribute = KeyValue::default();
        attribute.key = key.to_string();
        attribute.value = Some(any_value);

        self.context.last_mut().unwrap().attributes.push(attribute);
    }

    pub fn add_bool_attribute(&mut self, key: &str, value: bool) {
        debug_assert!(self.context.len() > 0, "No span to add attribute");

        let bool_value = any_value::Value::BoolValue(value);
        let any_value = AnyValue {
            value: Some(bool_value),
        };

        let mut attribute = KeyValue::default();
        attribute.key = key.to_string();
        attribute.value = Some(any_value);

        self.context.last_mut().unwrap().attributes.push(attribute);
    }

    pub fn add_int64_attribute(&mut self, key: &str, value: i64) {
        debug_assert!(self.context.len() > 0, "No span to add attribute");

        let int_value = any_value::Value::IntValue(value);
        let any_value = AnyValue {
            value: Some(int_value),
        };

        let mut attribute = KeyValue::default();
        attribute.key = key.to_string();
        attribute.value = Some(any_value);

        self.context.last_mut().unwrap().attributes.push(attribute);
    }

    pub fn add_double_attribute(&mut self, key: &str, value: f64) {
        debug_assert!(self.context.len() > 0, "No span to add attribute");

        let double_value = any_value::Value::DoubleValue(value);
        let any_value = AnyValue {
            value: Some(double_value),
        };

        let mut attribute = KeyValue::default();
        attribute.key = key.to_string();
        attribute.value = Some(any_value);

        self.context.last_mut().unwrap().attributes.push(attribute);
    }

    fn _gen_span_id(&mut self) -> [u8; 8] {
        let mut span_id = [0; 8];
        self.rng.fill_bytes(&mut span_id);
        span_id
    }
}

pub struct Metrics {
    metrics_data: MetricsData,
    resources_metrics: ResourceMetrics,
    scope_metrics: ScopeMetrics,
}

impl Metrics {
    pub fn new() -> Self {
        let mut scope_metrics = ScopeMetrics::default();
        scope_metrics.metrics.reserve(16);

        Metrics {
            metrics_data: MetricsData::default(),
            resources_metrics: ResourceMetrics::default(),
            scope_metrics,
        }
    }

    pub fn get_serialized(mut self, buf: &mut BytesMut) {
        let mut resource = Resource::default();
        resource.attributes.push(KeyValue {
            key: "service.name".to_string(),
            value: Some(AnyValue {
                value: Some(any_value::Value::StringValue(
                    "kong-gateway-qiqi-demo".to_string(),
                )),
            }),
        });
        resource.attributes.push(KeyValue {
            key: "service".to_string(),
            value: Some(AnyValue {
                value: Some(any_value::Value::StringValue(
                    "kong-gateway-qiqi-demo".to_string(),
                )),
            }),
        });
        resource.attributes.push(KeyValue {
            key: "env".to_string(),
            value: Some(AnyValue {
                value: Some(any_value::Value::StringValue("dev".to_string())),
            }),
        });

        self.resources_metrics.resource = Some(resource);
        self.resources_metrics
            .scope_metrics
            .push(self.scope_metrics);
        self.metrics_data
            .resource_metrics
            .push(self.resources_metrics);

        self.metrics_data.encode(buf).unwrap();
    }

    pub fn add_int64_gauge(&mut self, name: &str, value: i64) {
        let mut gauge = Gauge::default();
        let mut data_point = NumberDataPoint::default();

        data_point.time_unix_nano = _get_current_time_unix_nano();
        data_point.value = Some(Value::AsInt(value));

        gauge.data_points.push(data_point);

        let mut metric = Metric::default();
        metric.name = name.to_string();
        metric.data = Some(Data::Gauge(gauge));

        self.scope_metrics.metrics.push(metric);
    }

    pub fn add_double_gauge(&mut self, name: &str, value: f64) {
        let mut gauge = Gauge::default();
        let mut data_point = NumberDataPoint::default();

        data_point.time_unix_nano = _get_current_time_unix_nano();
        data_point.value = Some(Value::AsDouble(value));

        gauge.data_points.push(data_point);

        let mut metric = Metric::default();
        metric.name = name.to_string();
        metric.data = Some(Data::Gauge(gauge));

        self.scope_metrics.metrics.push(metric);
    }

    pub fn add_int64_sum(&mut self, name: &str, value: i64) {
        let mut sum = Sum::default();
        let mut data_point = NumberDataPoint::default();

        data_point.time_unix_nano = _get_current_time_unix_nano();
        data_point.value = Some(Value::AsInt(value));

        sum.data_points.push(data_point);

        let mut metric = Metric::default();
        metric.name = name.to_string();
        metric.data = Some(Data::Sum(sum));

        self.scope_metrics.metrics.push(metric);
    }

    pub fn add_double_sum(&mut self, name: &str, value: f64) {
        let mut sum = Sum::default();
        let mut data_point = NumberDataPoint::default();

        data_point.time_unix_nano = _get_current_time_unix_nano();
        data_point.value = Some(Value::AsDouble(value));

        sum.data_points.push(data_point);

        let mut metric = Metric::default();
        metric.name = name.to_string();
        metric.data = Some(Data::Sum(sum));

        self.scope_metrics.metrics.push(metric);
    }
}

pub struct Logs {
    logs_data: LogsData,
    resources_logs: ResourceLogs,
    scope_logs: ScopeLogs,
}

impl Logs {
    pub fn new() -> Self {
        let mut scope_logs = ScopeLogs::default();
        scope_logs.log_records.reserve(64);

        Logs {
            logs_data: LogsData::default(),
            resources_logs: ResourceLogs::default(),
            scope_logs,
        }
    }

    pub fn get_serialized(mut self, buf: &mut BytesMut) {
        let mut resource = Resource::default();
        resource.attributes.push(KeyValue {
            key: "service.name".to_string(),
            value: Some(AnyValue {
                value: Some(any_value::Value::StringValue(
                    "kong-gateway-qiqi-demo".to_string(),
                )),
            }),
        });
        resource.attributes.push(KeyValue {
            key: "service".to_string(),
            value: Some(AnyValue {
                value: Some(any_value::Value::StringValue(
                    "kong-gateway-qiqi-demo".to_string(),
                )),
            }),
        });
        resource.attributes.push(KeyValue {
            key: "env".to_string(),
            value: Some(AnyValue {
                value: Some(any_value::Value::StringValue("dev".to_string())),
            }),
        });

        self.resources_logs.resource = Some(resource);
        self.resources_logs.scope_logs.push(self.scope_logs);
        self.logs_data.resource_logs.push(self.resources_logs);

        self.logs_data.encode(buf).unwrap();
    }

    pub fn add_info_log(&mut self, time_unix_nano: u64, message: &str) {
        let mut log_record = LogRecord::default();
        log_record.time_unix_nano = time_unix_nano;
        log_record.observed_time_unix_nano = _get_current_time_unix_nano();
        log_record.severity_number = SeverityNumber::Info as i32;
        log_record.body = Some(AnyValue {
            value: Some(any_value::Value::StringValue(message.to_string())),
        });

        self.scope_logs.log_records.push(log_record);
    }

    pub fn add_notice_log(&mut self, time_unix_nano: u64, message: &str) {
        self.add_info_log(time_unix_nano, message);
    }

    pub fn add_warning_log(&mut self, time_unix_nano: u64, message: &str) {
        let mut log_record = LogRecord::default();
        log_record.time_unix_nano = time_unix_nano;
        log_record.observed_time_unix_nano = _get_current_time_unix_nano();
        log_record.severity_number = SeverityNumber::Warn as i32;
        log_record.body = Some(AnyValue {
            value: Some(any_value::Value::StringValue(message.to_string())),
        });

        self.scope_logs.log_records.push(log_record);
    }

    pub fn add_error_log(&mut self, time_unix_nano: u64, message: &str) {
        let mut log_record = LogRecord::default();
        log_record.time_unix_nano = time_unix_nano;
        log_record.observed_time_unix_nano = _get_current_time_unix_nano();
        log_record.severity_number = SeverityNumber::Error as i32;
        log_record.body = Some(AnyValue {
            value: Some(any_value::Value::StringValue(message.to_string())),
        });

        self.scope_logs.log_records.push(log_record);
    }

    pub fn add_fatal_log(&mut self, time_unix_nano: u64, message: &str) {
        let mut log_record = LogRecord::default();
        log_record.time_unix_nano = time_unix_nano;
        log_record.observed_time_unix_nano = _get_current_time_unix_nano();
        log_record.severity_number = SeverityNumber::Fatal as i32;
        log_record.body = Some(AnyValue {
            value: Some(any_value::Value::StringValue(message.to_string())),
        });

        self.scope_logs.log_records.push(log_record);
    }
}
