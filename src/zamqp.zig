const std = @import("std");

pub const boolean_t = c_int;
pub const method_number_t = u32;
pub const flags_t = u32;
pub const channel_t = u16;

pub const bytes_t = extern struct {
    len: usize,
    bytes: ?[*]const u8,

    pub fn init(buf: []const u8) bytes_t {
        if (buf.len == 0) return empty();
        return .{ .len = buf.len, .bytes = buf.ptr };
    }

    pub fn slice(self: bytes_t) ?[]const u8 {
        return (self.bytes orelse return null)[0..self.len];
    }

    extern fn amqp_cstring_bytes(cstr: [*:0]const u8) bytes_t;
    pub const initZ = amqp_cstring_bytes;

    pub fn empty() bytes_t {
        return amqp_empty_bytes;
    }
};

pub const array_t = extern struct {
    num_entries: c_int,
    entries: ?*opaque {},

    pub fn empty() array_t {
        return amqp_empty_array;
    }
};


pub const timeval_t = opaque {};

pub const method_t = extern struct {
    id: method_number_t,
    decoded: ?*c_void,
};

pub const connection_state_t = opaque {
    extern fn amqp_new_connection() ?*connection_state_t;
    pub fn new() !*connection_state_t {
        return amqp_new_connection() orelse error.LibraryException;
    }

    extern fn amqp_connection_close(state: *connection_state_t, code: c_int) rpc_reply_t;
    pub fn close(state: *connection_state_t, code: c_int) !void {
        return amqp_connection_close(state, code).ok();
    }

    extern fn amqp_destroy_connection(state: *connection_state_t) status_t;
    pub fn destroy(state: *connection_state_t) !void {
        return amqp_destroy_connection(state).ok();
    }

    extern fn amqp_maybe_release_buffers(state: *connection_state_t) void;
    pub const maybe_release_buffers = amqp_maybe_release_buffers;

    extern fn amqp_get_rpc_reply(state: *connection_state_t) rpc_reply_t;
    pub const last_rpc_reply = amqp_get_rpc_reply;

    pub fn login(state: *connection_state_t, vhost: [*:0]const u8, channel_max: c_int, frame_max: c_int, heartbeat: c_int, sasl_auth: SaslAuth) !void {
        return switch (sasl_auth) {
            .plain => |plain| amqp_login(state, vhost, channel_max, frame_max, heartbeat, .PLAIN, plain.username, plain.password),
            .external => |external| amqp_login(state, vhost, channel_max, frame_max, heartbeat, .EXTERNAL, external.identity),
        }.ok();
    }

    pub fn simple_wait_frame(state: *connection_state_t) !frame_t {
        var f: frame_t = undefined;
        amqp_simple_wait_frame(state, &f).ok();
        return f;
    }

    pub fn consume_message(state: *connection_state_t, timeout: ?*timeval_t, flags: c_int) !envelope_t {
        var e: envelope_t = undefined;
        try amqp_consume_message(state, &e, timeout, flags).ok();
        return e;
    }
};

extern fn amqp_login(state: *connection_state_t, vhost: [*:0]const u8, channel_max: c_int, frame_max: c_int, heartbeat: c_int, sasl_method: sasl_method_t, ...) rpc_reply_t;

extern fn amqp_consume_message(state: *connection_state_t, envelope_t: *envelope_t, timeout: ?*timeval_t, flags_t: c_int) rpc_reply_t;

extern fn amqp_simple_wait_frame(state: *connection_state_t, decoded_frame: *frame_t) status_t;

extern fn amqp_simple_wait_frame_noblock(state: *connection_state_t, decoded_frame: *frame_t, tv: ?*timeval_t) status_t;

pub const channel_open_ok_t = extern struct {
    channel_id: bytes_t,
};

pub const Channel = struct {
    conn: *connection_state_t,
    number: channel_t,

    pub fn open(self: Channel) !*channel_open_ok_t {
        return amqp_channel_open(self.conn, self.number) orelse self.conn.last_rpc_reply().err();
    }

    pub fn close(self: Channel, code: c_int) !void {
        return amqp_channel_close(self.conn, self.number, code).ok();
    }

    pub fn queue_declare(
        self: Channel,
        queue: bytes_t,
        passive: boolean_t,
        durable: boolean_t,
        exclusive: boolean_t,
        auto_delete: boolean_t,
        arguments: table_t,
    ) !*queue_declare_ok_t {
        return amqp_queue_declare(self.conn, self.number, queue, passive, durable, exclusive, auto_delete, arguments) orelse self.conn.last_rpc_reply().err();
    }

    pub fn basic_publish(
        self: Channel,
        exchange: bytes_t,
        routing_key: bytes_t,
        mandatory: boolean_t,
        immediate: boolean_t,
        properties: *const basic_properties_t,
        body: bytes_t,
    ) !void {
        return amqp_basic_publish(self.conn, self.number, exchange, routing_key, mandatory, immediate, properties, body).ok();
    }

    pub fn basic_consume(
        self: Channel,
        queue: bytes_t,
        consumer_tag: bytes_t,
        no_local: boolean_t,
        no_ack: boolean_t,
        exclusive: boolean_t,
        arguments: table_t,
    ) !*basic_consume_ok_t {
        return amqp_basic_consume(self.conn, self.number, queue, consumer_tag, no_local, no_ack, exclusive, arguments) orelse self.conn.last_rpc_reply().err();
    }

    pub fn basic_ack(self: Channel, delivery_tag: u64, multiple: boolean_t) c_int {
        return amqp_basic_ack(self.conn, self.number, delivery_tag, multiple);
    }

    pub fn maybe_release_buffers(self: Channel) void {
        amqp_maybe_release_buffers_on_channel(self.conn, self.number);
    }
};

extern fn amqp_channel_open(state: *connection_state_t, channel: channel_t) ?*channel_open_ok_t;

extern fn amqp_basic_publish(
    state: *connection_state_t,
    channel: channel_t,
    exchange: bytes_t,
    routing_key: bytes_t,
    mandatory: boolean_t,
    immediate: boolean_t,
    properties: *const basic_properties_t,
    body: bytes_t,
) status_t;

extern fn amqp_basic_consume(
    state: *connection_state_t,
    channel: channel_t,
    queue: bytes_t,
    consumer_tag: bytes_t,
    no_local: boolean_t,
    no_ack: boolean_t,
    exclusive: boolean_t,
    arguments: table_t,
) ?*basic_consume_ok_t;

extern fn amqp_queue_declare(
    state: *connection_state_t,
    channel: channel_t,
    queue: bytes_t,
    passive: boolean_t,
    durable: boolean_t,
    exclusive: boolean_t,
    auto_delete: boolean_t,
    arguments: table_t,
) ?*queue_declare_ok_t;

extern fn amqp_basic_ack(state: *connection_state_t, channel: channel_t, delivery_tag: u64, multiple: boolean_t) c_int;

extern fn amqp_channel_close(state: *connection_state_t, channel: channel_t, code: c_int) rpc_reply_t;

extern fn amqp_maybe_release_buffers_on_channel(state: *connection_state_t, channel: channel_t) void;

pub const socket_t = opaque {
    extern fn amqp_tcp_socket_new(state: *connection_state_t) ?*socket_t;
    pub fn new_tcp(state: *connection_state_t) !*socket_t {
        return amqp_tcp_socket_new(state) orelse error.LibraryException;
    }

    extern fn amqp_socket_open(self: *socket_t, host: [*:0]const u8, port: c_int) status_t;
    pub fn open(self: *socket_t, host: [*:0]const u8, port: c_int) !void {
        return amqp_socket_open(self, host, port).ok();
    }
};

pub const rpc_reply_t = extern struct {
    reply_type: response_type_t,
    reply: method_t,
    library_error: status_t,

    pub fn ok(self: rpc_reply_t) Error!void {
        return switch (self.reply_type) {
            .NORMAL => {},
            .NONE => error.SocketError,
            .LIBRARY_EXCEPTION => self.library_error.ok(),
            .SERVER_EXCEPTION => switch (self.reply.id) {
                CONNECTION_CLOSE_METHOD => error.ConnectionClosed,
                CHANNEL_CLOSE_METHOD => error.ChannelClosed,
                else => error.ServerException,
            },
            _ => error.Unexpected,
        };
    }

    pub fn err(self: rpc_reply_t) Error {
        return if (self.ok()) |_| error.Unexpected else |e| e;
    }
};

pub const basic_properties_t = extern struct {
    _flags: flags_t,
    content_type: bytes_t,
    content_encoding: bytes_t,
    headers: table_t,
    delivery_mode: u8,
    priority: u8,
    correlation_id: bytes_t,
    reply_to: bytes_t,
    expiration: bytes_t,
    message_id: bytes_t,
    timestamp: u64,
    @"type": bytes_t,
    user_id: bytes_t,
    app_id: bytes_t,
    cluster_id: bytes_t,

    pub const CONTENT_TYPE_FLAG = 1 << 15;
    pub const CONTENT_ENCODING_FLAG = 1 << 14;
    pub const HEADERS_FLAG = 1 << 13;
    pub const DELIVERY_MODE_FLAG = 1 << 12;
    pub const PRIORITY_FLAG = 1 << 11;
    pub const CORRELATION_ID_FLAG = 1 << 10;
    pub const REPLY_TO_FLAG = 1 << 9;
    pub const EXPIRATION_FLAG = 1 << 8;
    pub const MESSAGE_ID_FLAG = 1 << 7;
    pub const TIMESTAMP_FLAG = 1 << 6;
    pub const TYPE_FLAG = 1 << 5;
    pub const USER_ID_FLAG = 1 << 4;
    pub const APP_ID_FLAG = 1 << 3;
    pub const CLUSTER_ID_FLAG = 1 << 2;
};

pub const table_t = extern struct {
    num_entries: c_int,
    // entries: [*]table_entry_t,
    entries: *table_entry_t,

    pub fn empty() table_t {
        return amqp_empty_table;
    }
};

pub const table_entry_t = opaque {};
//  = extern struct {
//     key: bytes_t,
//     value: field_value,
// };

pub const queue_declare_ok_t = extern struct {
    queue: bytes_t,
    message_count: u32,
    consumer_count: u32,
};

pub const basic_consume_ok_t = extern struct {
    consumer_tag: bytes_t,
};

pub const queue_bind_ok_t = extern struct {
    dummy: u8,
};

pub const pool_blocklist_t = extern struct {
    num_blocks: c_int,
    blocklist: [*]?*c_void,
};

pub const pool_t = extern struct {
    pagesize: usize,
    pages: pool_blocklist_t,
    large_blocks: pool_blocklist_t,
    next_page: c_int,
    alloc_block: [*]u8,
    alloc_used: usize,
};

pub const message_t = extern struct {
    properties: basic_properties_t,
    body: bytes_t,
    pool: pool_t,

    pub fn destroy(self: *message_t) void {
        amqp_destroy_message(self);
    }
};

extern fn amqp_destroy_message(message: *message_t) void;

pub const envelope_t = extern struct {
    channel: channel_t,
    consumer_tag: bytes_t,
    delivery_tag: u64,
    redelivered: boolean_t,
    exchange: bytes_t,
    routing_key: bytes_t,
    message: message_t,

    pub fn destroy(self: *envelope_t) void {
        amqp_destroy_envelope(self);
    }
};

extern fn amqp_destroy_envelope(envelope_t: *envelope_t) void;

const frame_payload_properties_t = extern struct {
    class_id: u16,
    body_size: u64,
    decoded: ?*c_void,
    raw: bytes_t,
};
const frame_payload_protocol_header_t = extern struct {
    transport_high: u8,
    transport_low: u8,
    protocol_version_major: u8,
    protocol_version_minor: u8,
};
const frame_payload_t = extern union {
    method: method_t,
    properties: frame_payload_properties_t,
    body_fragment: bytes_t,
    protocol_header: frame_payload_protocol_header_t,
};
pub const frame_t = extern struct {
    frame_type: u8,
    channel: channel_t,
    payload: frame_payload_t,
};

extern const amqp_empty_bytes: bytes_t;
extern const amqp_empty_table: table_t;
extern const amqp_empty_array: array_t;

pub const response_type_t = extern enum(c_int) {
    NONE = 0,
    NORMAL = 1,
    LIBRARY_EXCEPTION = 2,
    SERVER_EXCEPTION = 3,
    _,
};

const sasl_method_t = extern enum(c_int) {
    UNDEFINED = -1,
    PLAIN = 0,
    EXTERNAL = 1,
    _,
};

pub const SaslAuth = union(enum) {
    plain: Plain,
    external: External,

    pub const Plain = struct {
        username: [*:0]const u8,
        password: [*:0]const u8,
    };

    pub const External = struct {
        identity: [*:0]const u8,
    };
};

pub const Error = LibraryError || ServerError;

pub const ServerError = error{
    ConnectionClosed,
    ChannelClosed,
    ServerException,
};

pub const LibraryError = error{
    UnexpectedState,
    OutOfMemory,
    Timeout,
    InvalidParameter,
    BadAmqpData,
    UnknownMethod,
    UnknownClass,
    HeartbeatTimeout,
    TimerFailure,
    SocketError,
    SslError,
    ConnectionClosed,
    LibraryException,
    Unexpected,
};

pub const status_t = extern enum(c_int) {
    OK = 0,
    NO_MEMORY = -1,
    BAD_AMQP_DATA = -2,
    UNKNOWN_CLASS = -3,
    UNKNOWN_METHOD = -4,
    HOSTNAME_RESOLUTION_FAILED = -5,
    INCOMPATIBLE_AMQP_VERSION = -6,
    CONNECTION_CLOSED = -7,
    BAD_URL = -8,
    SOCKET_ERROR = -9,
    INVALID_PARAMETER = -10,
    TABLE_TOO_BIG = -11,
    WRONG_METHOD = -12,
    TIMEOUT = -13,
    TIMER_FAILURE = -14,
    HEARTBEAT_TIMEOUT = -15,
    UNEXPECTED_STATE = -16,
    SOCKET_CLOSED = -17,
    SOCKET_INUSE = -18,
    BROKER_UNSUPPORTED_SASL_METHOD = -19,
    UNSUPPORTED = -20,
    _NEXT_VALUE = -21,
    TCP_ERROR = -256,
    TCP_SOCKETLIB_INIT_ERROR = -257,
    _TCP_NEXT_VALUE = -258,
    SSL_ERROR = -512,
    SSL_HOSTNAME_VERIFY_FAILED = -513,
    SSL_PEER_VERIFY_FAILED = -514,
    SSL_CONNECTION_FAILED = -515,
    _SSL_NEXT_VALUE = -516,
    _,

    pub fn ok(status: status_t) LibraryError!void {
        return switch (status) {
            .OK => {},
            .UNEXPECTED_STATE => error.UnexpectedState,
            .NO_MEMORY => error.OutOfMemory,
            .TIMEOUT => error.Timeout,
            .INVALID_PARAMETER => error.InvalidParameter,
            .BAD_AMQP_DATA => error.BadAmqpData,
            .UNKNOWN_METHOD => error.UnknownMethod,
            .UNKNOWN_CLASS => error.UnknownClass,
            .HEARTBEAT_TIMEOUT => error.HeartbeatTimeout,
            .TIMER_FAILURE => error.TimerFailure,
            .SOCKET_ERROR => error.SocketError,
            .SSL_ERROR => error.SslError,
            .CONNECTION_CLOSED => error.ConnectionClosed,
            ._NEXT_VALUE, ._TCP_NEXT_VALUE, ._SSL_NEXT_VALUE => error.Unexpected,
            else => error.LibraryException,
        };
    }

    extern fn amqp_error_string2(err: status_t) [*:0]const u8;
    pub const string = amqp_error_string2;
};

pub const REPLY_SUCCESS = 200;
pub const CONTENT_TOO_LARGE = 311;
pub const NO_ROUTE = 312;
pub const NO_CONSUMERS = 313;
pub const ACCESS_REFUSED = 403;
pub const NOT_FOUND = 404;
pub const RESOURCE_LOCKED = 405;
pub const PRECONDITION_FAILED = 406;
pub const CONNECTION_FORCED = 320;
pub const INVALID_PATH = 402;
pub const FRAME_ERROR = 501;
pub const SYNTAX_ERROR = 502;
pub const COMMAND_INVALID = 503;
pub const CHANNEL_ERROR = 504;
pub const UNEXPECTED_FRAME = 505;
pub const RESOURCE_ERROR = 506;
pub const NOT_ALLOWED = 530;
pub const NOT_IMPLEMENTED = 540;
pub const INTERNAL_ERROR = 541;

pub const CONNECTION_START_METHOD: method_number_t = 0x000A000A;
pub const CONNECTION_START_OK_METHOD: method_number_t = 0x000A000B;
pub const CONNECTION_SECURE_METHOD: method_number_t = 0x000A0014;
pub const CONNECTION_SECURE_OK_METHOD: method_number_t = 0x000A0015;
pub const CONNECTION_TUNE_METHOD: method_number_t = 0x000A001E;
pub const CONNECTION_TUNE_OK_METHOD: method_number_t = 0x000A001F;
pub const CONNECTION_OPEN_METHOD: method_number_t = 0x000A0028;
pub const CONNECTION_OPEN_OK_METHOD: method_number_t = 0x000A0029;
pub const CONNECTION_CLOSE_METHOD: method_number_t = 0x000A0032;
pub const CONNECTION_CLOSE_OK_METHOD: method_number_t = 0x000A0033;
pub const CONNECTION_BLOCKED_METHOD: method_number_t = 0x000A003C;
pub const CONNECTION_UNBLOCKED_METHOD: method_number_t = 0x000A003D;
pub const CHANNEL_OPEN_METHOD: method_number_t = 0x0014000A;
pub const CHANNEL_OPEN_OK_t_METHOD: method_number_t = 0x0014000B;
pub const CHANNEL_FLOW_METHOD: method_number_t = 0x00140014;
pub const CHANNEL_FLOW_OK_METHOD: method_number_t = 0x00140015;
pub const CHANNEL_CLOSE_METHOD: method_number_t = 0x00140028;
pub const CHANNEL_CLOSE_OK_METHOD: method_number_t = 0x00140029;
pub const ACCESS_REQUEST_METHOD: method_number_t = 0x001E000A;
pub const ACCESS_REQUEST_OK_METHOD: method_number_t = 0x001E000B;
pub const EXCHANGE_DECLARE_METHOD: method_number_t = 0x0028000A;
pub const EXCHANGE_DECLARE_OK_METHOD: method_number_t = 0x0028000B;
pub const EXCHANGE_DELETE_METHOD: method_number_t = 0x00280014;
pub const EXCHANGE_DELETE_OK_METHOD: method_number_t = 0x00280015;
pub const EXCHANGE_BIND_METHOD: method_number_t = 0x0028001E;
pub const EXCHANGE_BIND_OK_METHOD: method_number_t = 0x0028001F;
pub const EXCHANGE_UNBIND_METHOD: method_number_t = 0x00280028;
pub const EXCHANGE_UNBIND_OK_METHOD: method_number_t = 0x00280033;
pub const QUEUE_DECLARE_METHOD: method_number_t = 0x0032000A;
pub const QUEUE_DECLARE_OK_METHOD: method_number_t = 0x0032000B;
pub const QUEUE_BIND_METHOD: method_number_t = 0x00320014;
pub const QUEUE_BIND_OK_METHOD: method_number_t = 0x00320015;
pub const QUEUE_PURGE_METHOD: method_number_t = 0x0032001E;
pub const QUEUE_PURGE_OK_METHOD: method_number_t = 0x0032001F;
pub const QUEUE_DELETE_METHOD: method_number_t = 0x00320028;
pub const QUEUE_DELETE_OK_METHOD: method_number_t = 0x00320029;
pub const QUEUE_UNBIND_METHOD: method_number_t = 0x00320032;
pub const QUEUE_UNBIND_OK_METHOD: method_number_t = 0x00320033;
pub const BASIC_QOS_METHOD: method_number_t = 0x003C000A;
pub const BASIC_QOS_OK_METHOD: method_number_t = 0x003C000B;
pub const BASIC_CONSUME_METHOD: method_number_t = 0x003C0014;
pub const BASIC_CONSUME_OK_METHOD: method_number_t = 0x003C0015;
pub const BASIC_CANCEL_METHOD: method_number_t = 0x003C001E;
pub const BASIC_CANCEL_OK_METHOD: method_number_t = 0x003C001F;
pub const BASIC_PUBLISH_METHOD: method_number_t = 0x003C0028;
pub const BASIC_RETURN_METHOD: method_number_t = 0x003C0032;
pub const BASIC_DELIVER_METHOD: method_number_t = 0x003C003C;
pub const BASIC_GET_METHOD: method_number_t = 0x003C0046;
pub const BASIC_GET_OK_METHOD: method_number_t = 0x003C0047;
pub const BASIC_GET_EMPTY_METHOD: method_number_t = 0x003C0048;
pub const BASIC_ACK_METHOD: method_number_t = 0x003C0050;
pub const BASIC_REJECT_METHOD: method_number_t = 0x003C005A;
pub const BASIC_RECOVER_ASYNC_METHOD: method_number_t = 0x003C0064;
pub const BASIC_RECOVER_METHOD: method_number_t = 0x003C006E;
pub const BASIC_RECOVER_OK_METHOD: method_number_t = 0x003C006F;
pub const BASIC_NACK_METHOD: method_number_t = 0x003C0078;
pub const TX_SELECT_METHOD: method_number_t = 0x005A000A;
pub const TX_SELECT_OK_METHOD: method_number_t = 0x005A000B;
pub const TX_COMMIT_METHOD: method_number_t = 0x005A0014;
pub const TX_COMMIT_OK_METHOD: method_number_t = 0x005A0015;
pub const TX_ROLLBACK_METHOD: method_number_t = 0x005A001E;
pub const TX_ROLLBACK_OK_METHOD: method_number_t = 0x005A001F;
pub const CONFIRM_SELECT_METHOD: method_number_t = 0x0055000A;
pub const CONFIRM_SELECT_OK_METHOD: method_number_t = 0x0055000B;

pub const connection_close_t = extern struct {
    reply_code: u16,
    reply_text: bytes_t,
    class_id: u16,
    method_id: u16,
};

pub const channel_close_t = extern struct {
    reply_code: u16,
    reply_text: bytes_t,
    class_id: u16,
    method_id: u16,
};

// pub const decimal = extern struct {
//     decimals: u8,
//     value: u32,
// };
// const union_unnamed_3 = extern union {
//     boolean_t: boolean_t,
//     i8: i8,
//     u8: u8,
//     i16: i16,
//     u16: u16,
//     i32: i32,
//     u32: u32,
//     i64: i64,
//     u64: u64,
//     f32: f32,
//     f64: f64,
//     decimal: decimal,
//     bytes_t: bytes_t,
//     table_t: amqp_table_t,
//     array_t: array_t,
// };
// pub const field_value = extern struct {
//     kind: u8,
//     value: union_unnamed_3,
// };

