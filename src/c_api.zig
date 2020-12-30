usingnamespace @import("zamqp.zig");

// Connection
pub const connection_state_t = opaque {};

pub extern fn amqp_new_connection() ?*connection_state_t;
pub extern fn amqp_connection_close(state: *connection_state_t, code: c_int) RpcReply;
pub extern fn amqp_destroy_connection(state: *connection_state_t) status_t;
pub extern fn amqp_login(state: *connection_state_t, vhost: [*:0]const u8, channel_max: c_int, frame_max: c_int, heartbeat: c_int, sasl_method: sasl_method_t, ...) RpcReply;
pub extern fn amqp_maybe_release_buffers(state: *connection_state_t) void;
pub extern fn amqp_get_rpc_reply(state: *connection_state_t) RpcReply;
pub extern fn amqp_simple_wait_frame_noblock(state: *connection_state_t, decoded_frame: *Frame, tv: ?*timeval_t) status_t;
pub extern fn amqp_consume_message(state: *connection_state_t, envelope: *Envelope, timeout: ?*timeval_t, flags_t: c_int) RpcReply;

// Socket
pub const socket_t = opaque {};

pub extern fn amqp_socket_open(self: *socket_t, host: [*:0]const u8, port: c_int) status_t;

pub extern fn amqp_tcp_socket_new(state: *connection_state_t) ?*socket_t;
pub extern fn amqp_tcp_socket_set_sockfd(self: *socket_t, sockfd: c_int) void;

pub extern fn amqp_ssl_socket_new(state: *connection_state_t) ?*amqp_socket_t;
pub extern fn amqp_ssl_socket_set_cacert(self: *socket_t, cacert: [*:0]const u8) status_t;
pub extern fn amqp_ssl_socket_set_key(self: *socket_t, cert: [*:0]const u8, key: [*:0]const u8) status_t;
pub extern fn amqp_ssl_socket_set_key_buffer(self: *socket_t, cert: [*:0]const u8, key: ?*const c_void, n: usize) status_t;
pub extern fn amqp_ssl_socket_set_verify(self: *socket_t, verify: boolean_t) void;
pub extern fn amqp_ssl_socket_set_verify_peer(self: *socket_t, verify: boolean_t) void;
pub extern fn amqp_ssl_socket_set_verify_hostname(self: *socket_t, verify: boolean_t) void;
pub extern fn amqp_ssl_socket_set_ssl_versions(self: *socket_t, min: tls_version_t, max: tls_version_t) status_t;

// Channel

pub extern fn amqp_channel_open(state: *connection_state_t, channel: channel_t) ?*channel_open_ok_t;
pub extern fn amqp_read_message(state: *connection_state_t, channel: channel_t, message: *Message, flags: c_int) RpcReply;
pub extern fn amqp_basic_publish(
    state: *connection_state_t,
    channel: channel_t,
    exchange: bytes_t,
    routing_key: bytes_t,
    mandatory: boolean_t,
    immediate: boolean_t,
    properties: *const BasicProperties,
    body: bytes_t,
) status_t;
pub extern fn amqp_basic_consume(
    state: *connection_state_t,
    channel: channel_t,
    queue: bytes_t,
    consumer_tag: bytes_t,
    no_local: boolean_t,
    no_ack: boolean_t,
    exclusive: boolean_t,
    arguments: table_t,
) ?*basic_consume_ok_t;
pub extern fn amqp_queue_declare(
    state: *connection_state_t,
    channel: channel_t,
    queue: bytes_t,
    passive: boolean_t,
    durable: boolean_t,
    exclusive: boolean_t,
    auto_delete: boolean_t,
    arguments: table_t,
) ?*queue_declare_ok_t;
pub extern fn amqp_basic_ack(state: *connection_state_t, channel: channel_t, delivery_tag: u64, multiple: boolean_t) status_t;
pub extern fn amqp_channel_close(state: *connection_state_t, channel: channel_t, code: c_int) RpcReply;
pub extern fn amqp_maybe_release_buffers_on_channel(state: *connection_state_t, channel: channel_t) void;

pub extern fn amqp_destroy_message(message: *Message) void;

pub extern fn amqp_destroy_envelope(envelope: *Envelope) void;


pub extern const amqp_empty_bytes: bytes_t;
pub extern const amqp_empty_table: table_t;
pub extern const amqp_empty_array: array_t;

pub const sasl_method_t = extern enum(c_int) {
    UNDEFINED = -1,
    PLAIN = 0,
    EXTERNAL = 1,
    _,
};
