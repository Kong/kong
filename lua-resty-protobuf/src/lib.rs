mod ffi;

use prost::Message;
use rand::prelude::*;
use std::time;

use bytes::{BytesMut, BufMut};

use opentelemetry_proto::tonic::{
    common::v1::{any_value, AnyValue, KeyValue},
    trace::v1::Span,
};

const DEFAULT_CONTEXT_CAPACITY: usize = 16;
const DEFAULT_SERIALIZED_CAPACITY: usize = 2048;
const MAX_BUFFER_SIZE: usize = 64 * 1024 - 1 - 8 - 20;

static mut udp_socket: Option<std::net::UdpSocket> = None;
static mut buffer: Option<BytesMut> = None;

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

pub struct Trace {
    rng: ThreadRng,
    context: Vec<Span>,

    trace_id: [u8; 16],

    serialized: BytesMut,
}

impl Trace {
    pub fn new() -> Self {
        let mut rng = thread_rng();
        let mut trace_id = [0; 16];
        rng.fill_bytes(&mut trace_id);

        Trace {
            rng,
            context: Vec::with_capacity(DEFAULT_CONTEXT_CAPACITY),
            trace_id,
            serialized: BytesMut::with_capacity(DEFAULT_SERIALIZED_CAPACITY),
        }
    }

    pub fn get_serialized(&self) -> &[u8] {
        &self.serialized
    }

    pub fn enter_span(&mut self, name: &str) {
        let mut span = Span::default();
        span.trace_id = self.trace_id.to_vec();
        span.span_id = self._gen_span_id().to_vec();
        span.name = name.to_string();
        span.start_time_unix_nano = _get_current_time_unix_nano();

        self.context.push(span);
    }

    pub fn exit_span(&mut self) {
        debug_assert!(self.context.len() > 0, "No span to exit");

        let span = self.context.last_mut().unwrap();
        span.end_time_unix_nano = _get_current_time_unix_nano();

        span.encode(&mut self.serialized).unwrap();

        self.context.pop();
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
    }

    pub unsafe fn send_to_udp(&self) {
        if udp_socket.is_none() {
            udp_socket = Some(std::net::UdpSocket::bind("127.0.0.1:0").unwrap());
            udp_socket.as_mut().unwrap().connect("127.0.0.1:9999").unwrap();
        }

        if buffer.is_none() {
            buffer = Some(BytesMut::with_capacity(DEFAULT_SERIALIZED_CAPACITY));
        }

        let socket = udp_socket.as_ref().unwrap();
        let buf = buffer.as_mut().unwrap();

        assert!(self.serialized.len() < MAX_BUFFER_SIZE, "Serialized data too large");
        
        if buf.len() + self.serialized.len() >= MAX_BUFFER_SIZE {
            socket.send(&buf).unwrap();
            buf.clear();
        }

        buf.extend_from_slice(&self.serialized);
    }

    fn _gen_span_id(&mut self) -> [u8; 8] {
        let mut span_id = [0; 8];
        self.rng.fill_bytes(&mut span_id);
        span_id
    }
}
