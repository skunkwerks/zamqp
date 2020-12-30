const std = @import("std");
const meta = std.meta;
const c = std.c;

usingnamespace @import("c_api.zig");

const log = std.log.scoped(.zamqp);

pub const boolean_t = c_int;
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
        return .{ .len = 0, .bytes = null };
    }
};

pub const array_t = extern struct {
    num_entries: c_int,
    entries: ?*opaque {},

    pub fn empty() array_t {
        return .{ .num_entries = 0, .entries = null };
    }
};

pub const table_t = extern struct {
    num_entries: c_int,
    entries: ?*opaque {},

    pub fn empty() table_t {
        return .{ .num_entries = 0, .entries = null };
    }
};

pub const method_t = extern struct {
    id: method_number_t,
    decoded: ?*c_void,
};

pub const DEFAULT_FRAME_SIZE: c_int = 131072;
pub const DEFAULT_MAX_CHANNELS: c_int = 2047;
// pub const DEFAULT_HEARTBEAT: c_int = 0;
// pub const DEFAULT_VHOST = "/";

pub const Connection = struct {
    handle: *connection_state_t,

    pub fn new() error{OutOfMemory}!Connection {
        return Connection{ .handle = amqp_new_connection() orelse return error.OutOfMemory };
    }

    pub fn close(self: Connection, code: ReplyCode) !void {
        return amqp_connection_close(self.handle, @enumToInt(code)).ok();
    }

    pub fn destroy(self: *Connection) !void {
        const status = amqp_destroy_connection(self.handle);
        self.handle = undefined;
        return status.ok();
    }

    pub fn maybe_release_buffers(self: Connection) void {
        amqp_maybe_release_buffers(self.handle);
    }

    /// Not every function updates this. See docs of `amqp_get_rpc_reply`.
    pub fn last_rpc_reply(self: Connection) RpcReply {
        return amqp_get_rpc_reply(self.handle);
    }

    pub fn login(
        self: Connection,
        vhost: [*:0]const u8,
        sasl_auth: SaslAuth,
        extra: struct {
            heartbeat: c_int,
            channel_max: c_int = DEFAULT_MAX_CHANNELS,
            frame_max: c_int = DEFAULT_FRAME_SIZE,
        },
    ) !void {
        return switch (sasl_auth) {
            .plain => |plain| amqp_login(self.handle, vhost, extra.channel_max, extra.frame_max, extra.heartbeat, .PLAIN, plain.username, plain.password),
            .external => |external| amqp_login(self.handle, vhost, extra.channel_max, extra.frame_max, extra.heartbeat, .EXTERNAL, external.identity),
        }.ok();
    }

    pub fn simple_wait_frame(self: Connection, timeout: ?*c.timeval) !Frame {
        var f: Frame = undefined;
        try amqp_simple_wait_frame_noblock(self.handle, &f, timeout).ok();
        return f;
    }

    pub fn consume_message(self: Connection, timeout: ?*c.timeval, flags: c_int) !Envelope {
        var e: Envelope = undefined;
        try amqp_consume_message(self.handle, &e, timeout, flags).ok();
        return e;
    }

    pub fn channel(self: Connection, number: channel_t) Channel {
        return .{ .connection = self, .number = number };
    }

    pub const SaslAuth = union(enum) {
        plain: struct {
            username: [*:0]const u8,
            password: [*:0]const u8,
        },
        external: struct {
            identity: [*:0]const u8,
        },
    };
};

pub const Channel = struct {
    connection: Connection,
    number: channel_t,

    pub fn open(self: Channel) !*channel_open_ok_t {
        return amqp_channel_open(self.connection.handle, self.number) orelse self.connection.last_rpc_reply().err();
    }

    pub fn close(self: Channel, code: ReplyCode) !void {
        return amqp_channel_close(self.connection.handle, self.number, @enumToInt(code)).ok();
    }

    pub fn queue_declare(
        self: Channel,
        queue: bytes_t,
        extra: struct {
            passive: bool = false,
            durable: bool = false,
            exclusive: bool = false,
            auto_delete: bool = false,
            arguments: table_t = table_t.empty(),
        },
    ) !*queue_declare_ok_t {
        return amqp_queue_declare(
            self.connection.handle,
            self.number,
            queue,
            @boolToInt(extra.passive),
            @boolToInt(extra.durable),
            @boolToInt(extra.exclusive),
            @boolToInt(extra.auto_delete),
            extra.arguments,
        ) orelse self.connection.last_rpc_reply().err();
    }

    pub fn basic_publish(
        self: Channel,
        exchange: bytes_t,
        routing_key: bytes_t,
        body: bytes_t,
        properties: BasicProperties,
        extra: struct {
            mandatory: bool = false,
            immediate: bool = false,
        },
    ) !void {
        return amqp_basic_publish(
            self.connection.handle,
            self.number,
            exchange,
            routing_key,
            @boolToInt(extra.mandatory),
            @boolToInt(extra.immediate),
            &properties,
            body,
        ).ok();
    }

    pub fn basic_consume(
        self: Channel,
        queue: bytes_t,
        extra: struct {
            consumer_tag: bytes_t = bytes_t.empty(),
            no_local: bool = false,
            no_ack: bool = false,
            exclusive: bool = false,
            arguments: table_t = table_t.empty(),
        },
    ) !*basic_consume_ok_t {
        return amqp_basic_consume(
            self.connection.handle,
            self.number,
            queue,
            extra.consumer_tag,
            @boolToInt(extra.no_local),
            @boolToInt(extra.no_ack),
            @boolToInt(extra.exclusive),
            extra.arguments,
        ) orelse self.connection.last_rpc_reply().err();
    }

    pub fn basic_ack(self: Channel, delivery_tag: u64, multiple: bool) !void {
        return amqp_basic_ack(self.connection.handle, self.number, delivery_tag, @boolToInt(multiple)).ok();
    }

    pub fn basic_reject(self: Channel, delivery_tag: u64, requeue: bool) !void {
        return amqp_basic_reject(self.connection.handle, self.number, delivery_tag, @boolToInt(requeue)).ok();
    }

    pub fn read_message(self: Channel, flags: c_int) !Message {
        var msg: Message = undefined;
        try amqp_read_message(self.connection.handle, self.number, &msg, flags).ok();
        return msg;
    }

    pub fn maybe_release_buffers(self: Channel) void {
        amqp_maybe_release_buffers_on_channel(self.connection.handle, self.number);
    }
};

pub const TcpSocket = struct {
    handle: *socket_t,

    pub fn new(connection: Connection) error{OutOfMemory}!TcpSocket {
        return TcpSocket{ .handle = amqp_tcp_socket_new(connection.handle) orelse return error.OutOfMemory };
    }

    pub fn set_sockfd(self: TcpSocket, sockfd: c_int) void {
        amqp_tcp_socket_set_sockfd(self.handle, sockfd);
    }

    pub fn open(self: TcpSocket, host: [*:0]const u8, port: c_int, timeout: ?*c.timeval) !void {
        return amqp_socket_open_noblock(self.handle, host, port, timeout).ok();
    }
};

pub const SslSocket = struct {
    handle: *socket_t,

    pub fn new(connection: Connection) error{OutOfMemory}!SslSocket {
        return SslSocket{ .handle = amqp_ssl_socket_new(connection.handle) orelse return error.OutOfMemory };
    }

    pub fn open(self: SslSocket, host: [*:0]const u8, port: c_int, timeout: ?*c.timeval) !void {
        return amqp_socket_open_noblock(self.handle, host, port, timeout).ok();
    }

    pub fn set_cacert(self: SslSocket, cacert: [*:0]const u8) !void {
        return amqp_ssl_socket_set_cacert(self.handle, cacert).ok();
    }

    pub fn set_keyZ(self: SslSocket, cert: [*:0]const u8, key: [*:0]const u8) !void {
        return amqp_ssl_socket_set_key(self.handle, cert, key).ok();
    }

    pub fn set_key(self: SslSocket, cert: [*:0]const u8, key: []const u8) !void {
        return amqp_ssl_socket_set_key_buffer(self.handle, cert, key.ptr, key.len).ok();
    }

    pub fn set_verify(self: SslSocket, verify: bool) void {
        amqp_ssl_socket_set_verify(self.handle, @boolToInt(verify));
    }

    pub fn set_verify_peer(self: SslSocket, verify: bool) void {
        amqp_ssl_socket_set_verify_peer(self.handle, @boolToInt(verify));
    }

    pub fn set_verify_hostname(self: SslSocket, verify: bool) void {
        amqp_ssl_socket_set_verify_hostname(self.handle, @boolToInt(verify));
    }

    pub fn set_ssl_versions(self: SslSocket, min: TlsVersion, max: TlsVersion) error{ Unsupported, InvalidParameter, Unexpected }!void {
        return switch (amqp_ssl_socket_set_ssl_versions(self.handle, min, max)) {
            .OK => {},
            .UNSUPPORTED => error.Unsupported,
            .INVALID_PARAMETER => error.InvalidParameter,
            else => |code| unexpected(code),
        };
    }

    const TlsVersion = extern enum(c_int) {
        AMQP_TLSv1 = 1,
        AMQP_TLSv1_1 = 2,
        AMQP_TLSv1_2 = 3,
        AMQP_TLSvLATEST = 65535,
        _,
    };
};

pub const RpcReply = extern struct {
    reply_type: response_type_t,
    reply: method_t,
    library_error: status_t,

    pub fn ok(self: RpcReply) Error!void {
        return switch (self.reply_type) {
            .NORMAL => {},
            .NONE => error.SocketError,
            .LIBRARY_EXCEPTION => self.library_error.ok(),
            .SERVER_EXCEPTION => switch (self.reply.id) {
                .CONNECTION_CLOSE => error.ConnectionClosed,
                .CHANNEL_CLOSE => error.ChannelClosed,
                else => error.UnexpectedReply,
            },
            _ => {
                log.crit("unexpected librabbitmq response type, value {}", .{self.reply_type});
                return error.Unexpected;
            },
        };
    }

    pub fn err(self: RpcReply) Error {
        if (self.ok()) |_| {
            log.crit("expected librabbitmq error, got success instead", .{});
            return error.Unexpected;
        } else |e| return e;
    }

    pub const response_type_t = extern enum(c_int) {
        NONE = 0,
        NORMAL = 1,
        LIBRARY_EXCEPTION = 2,
        SERVER_EXCEPTION = 3,
        _,
    };
};

/// Do not use fields directly to avoid bugs.
pub const BasicProperties = extern struct {
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
    type_: bytes_t,
    user_id: bytes_t,
    app_id: bytes_t,
    cluster_id: bytes_t,

    pub fn init(fields: anytype) BasicProperties {
        var props: BasicProperties = undefined;
        props._flags = 0;

        inline for (meta.fields(@TypeOf(fields))) |f| {
            @field(props, f.name) = @field(fields, f.name);
            props._flags |= @enumToInt(@field(BasicProperties.Flag, f.name));
        }

        return props;
    }

    pub fn get(self: BasicProperties, comptime flag: Flag) ?flag.Type() {
        if (self._flags & @enumToInt(flag) == 0) return null;
        return @field(self, @tagName(flag));
    }

    pub fn set(self: *BasicProperties, comptime flag: Flag, value: ?flag.Type()) void {
        if (value) |val| {
            self._flags |= @enumToInt(flag);
            @field(self, @tagName(flag)) = val;
        } else {
            self._flags &= ~@enumToInt(flag);
            @field(self, @tagName(flag)) = undefined;
        }
    }

    pub const Flag = extern enum(flags_t) {
        content_type = 1 << 15,
        content_encoding = 1 << 14,
        headers = 1 << 13,
        delivery_mode = 1 << 12,
        priority = 1 << 11,
        correlation_id = 1 << 10,
        reply_to = 1 << 9,
        expiration = 1 << 8,
        message_id = 1 << 7,
        timestamp = 1 << 6,
        type_ = 1 << 5,
        user_id = 1 << 4,
        app_id = 1 << 3,
        cluster_id = 1 << 2,
        _,

        pub fn Type(flag: Flag) type {
            return meta.fieldInfo(BasicProperties, @tagName(flag)).field_type;
        }
    };
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

pub const Message = extern struct {
    properties: BasicProperties,
    body: bytes_t,
    pool: pool_t,

    pub fn destroy(self: *Message) void {
        amqp_destroy_message(self);
    }
};

pub const Envelope = extern struct {
    channel: channel_t,
    consumer_tag: bytes_t,
    delivery_tag: u64,
    redelivered: boolean_t,
    exchange: bytes_t,
    routing_key: bytes_t,
    message: Message,

    pub fn destroy(self: *Envelope) void {
        amqp_destroy_envelope(self);
    }
};

pub const Frame = extern struct {
    frame_type: Type,
    channel: channel_t,
    payload: extern union {
        /// frame_type == .METHOD
        method: method_t,
        /// frame_type == .HEADER
        properties: extern struct {
            class_id: u16,
            body_size: u64,
            decoded: ?*c_void,
            raw: bytes_t,
        },
        /// frame_type == BODY
        body_fragment: bytes_t,
        /// used during initial handshake
        protocol_header: extern struct {
            transport_high: u8,
            transport_low: u8,
            protocol_version_major: u8,
            protocol_version_minor: u8,
        },
    },

    pub const Type = extern enum(u8) {
        METHOD = 1,
        HEADER = 2,
        BODY = 3,
        _,
    };
};

pub const Error = LibraryError || ServerError;

pub const ServerError = error{
    ConnectionClosed,
    ChannelClosed,
    UnexpectedReply,
};

pub const LibraryError = error{
    OutOfMemory,
    BadAmqpData,
    UnknownClass,
    UnknownMethod,
    HostnameResolutionFailed,
    IncompatibleAmqpVersion,
    ConnectionClosed,
    BadUrl,
    SocketError,
    InvalidParameter,
    TableTooBig,
    WrongMethod,
    Timeout,
    TimerFailure,
    HeartbeatTimeout,
    UnexpectedState,
    SocketClosed,
    SocketInUse,
    BrokerUnsupportedSaslMethod,
    Unsupported,
    TcpError,
    TcpSocketlibInitError,
    SslError,
    SslHostnameVerifyFailed,
    SslPeerVerifyFailed,
    SslConnectionFailed,
    Unexpected,
};

fn unexpected(status: status_t) error{Unexpected} {
    log.crit("unexpected librabbitmq error, code {}, message {s}", .{ status, status.string() });
    return error.Unexpected;
}

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
    TCP_ERROR = -256,
    TCP_SOCKETLIB_INIT_ERROR = -257,
    SSL_ERROR = -512,
    SSL_HOSTNAME_VERIFY_FAILED = -513,
    SSL_PEER_VERIFY_FAILED = -514,
    SSL_CONNECTION_FAILED = -515,
    _,

    pub fn ok(status: status_t) LibraryError!void {
        return switch (status) {
            .OK => {},
            .NO_MEMORY => error.OutOfMemory,
            .BAD_AMQP_DATA => error.BadAmqpData,
            .UNKNOWN_CLASS => error.UnknownClass,
            .UNKNOWN_METHOD => error.UnknownMethod,
            .HOSTNAME_RESOLUTION_FAILED => error.HostnameResolutionFailed,
            .INCOMPATIBLE_AMQP_VERSION => error.IncompatibleAmqpVersion,
            .CONNECTION_CLOSED => error.ConnectionClosed,
            .BAD_URL => error.BadUrl,
            .SOCKET_ERROR => error.SocketError,
            .INVALID_PARAMETER => error.InvalidParameter,
            .TABLE_TOO_BIG => error.TableTooBig,
            .WRONG_METHOD => error.WrongMethod,
            .TIMEOUT => error.Timeout,
            .TIMER_FAILURE => error.TimerFailure,
            .HEARTBEAT_TIMEOUT => error.HeartbeatTimeout,
            .UNEXPECTED_STATE => error.UnexpectedState,
            .SOCKET_CLOSED => error.SocketClosed,
            .SOCKET_INUSE => error.SocketInUse,
            .BROKER_UNSUPPORTED_SASL_METHOD => error.BrokerUnsupportedSaslMethod,
            .UNSUPPORTED => error.Unsupported,
            .TCP_ERROR => error.TcpError,
            .TCP_SOCKETLIB_INIT_ERROR => error.TcpSocketlibInitError,
            .SSL_ERROR => error.SslError,
            .SSL_HOSTNAME_VERIFY_FAILED => error.SslHostnameVerifyFailed,
            .SSL_PEER_VERIFY_FAILED => error.SslPeerVerifyFailed,
            .SSL_CONNECTION_FAILED => error.SslConnectionFailed,
            _ => unexpected(status),
        };
    }

    extern fn amqp_error_string2(err: status_t) [*:0]const u8;
    pub const string = amqp_error_string2;
};

pub const ReplyCode = extern enum(u16) {
    REPLY_SUCCESS = 200,
    CONTENT_TOO_LARGE = 311,
    NO_ROUTE = 312,
    NO_CONSUMERS = 313,
    ACCESS_REFUSED = 403,
    NOT_FOUND = 404,
    RESOURCE_LOCKED = 405,
    PRECONDITION_FAILED = 406,
    CONNECTION_FORCED = 320,
    INVALID_PATH = 402,
    FRAME_ERROR = 501,
    SYNTAX_ERROR = 502,
    COMMAND_INVALID = 503,
    CHANNEL_ERROR = 504,
    UNEXPECTED_FRAME = 505,
    RESOURCE_ERROR = 506,
    NOT_ALLOWED = 530,
    NOT_IMPLEMENTED = 540,
    INTERNAL_ERROR = 541,
};

pub const method_number_t = extern enum(u32) {
    CONNECTION_START = 0x000A000A,
    CONNECTION_START_OK = 0x000A000B,
    CONNECTION_SECURE = 0x000A0014,
    CONNECTION_SECURE_OK = 0x000A0015,
    CONNECTION_TUNE = 0x000A001E,
    CONNECTION_TUNE_OK = 0x000A001F,
    CONNECTION_OPEN = 0x000A0028,
    CONNECTION_OPEN_OK = 0x000A0029,
    CONNECTION_CLOSE = 0x000A0032,
    CONNECTION_CLOSE_OK = 0x000A0033,
    CONNECTION_BLOCKED = 0x000A003C,
    CONNECTION_UNBLOCKED = 0x000A003D,
    CHANNEL_OPEN = 0x0014000A,
    CHANNEL_OPEN_OK = 0x0014000B,
    CHANNEL_FLOW = 0x00140014,
    CHANNEL_FLOW_OK = 0x00140015,
    CHANNEL_CLOSE = 0x00140028,
    CHANNEL_CLOSE_OK = 0x00140029,
    ACCESS_REQUEST = 0x001E000A,
    ACCESS_REQUEST_OK = 0x001E000B,
    EXCHANGE_DECLARE = 0x0028000A,
    EXCHANGE_DECLARE_OK = 0x0028000B,
    EXCHANGE_DELETE = 0x00280014,
    EXCHANGE_DELETE_OK = 0x00280015,
    EXCHANGE_BIND = 0x0028001E,
    EXCHANGE_BIND_OK = 0x0028001F,
    EXCHANGE_UNBIND = 0x00280028,
    EXCHANGE_UNBIND_OK = 0x00280033,
    QUEUE_DECLARE = 0x0032000A,
    QUEUE_DECLARE_OK = 0x0032000B,
    QUEUE_BIND = 0x00320014,
    QUEUE_BIND_OK = 0x00320015,
    QUEUE_PURGE = 0x0032001E,
    QUEUE_PURGE_OK = 0x0032001F,
    QUEUE_DELETE = 0x00320028,
    QUEUE_DELETE_OK = 0x00320029,
    QUEUE_UNBIND = 0x00320032,
    QUEUE_UNBIND_OK = 0x00320033,
    BASIC_QOS = 0x003C000A,
    BASIC_QOS_OK = 0x003C000B,
    BASIC_CONSUME = 0x003C0014,
    BASIC_CONSUME_OK = 0x003C0015,
    BASIC_CANCEL = 0x003C001E,
    BASIC_CANCEL_OK = 0x003C001F,
    BASIC_PUBLISH = 0x003C0028,
    BASIC_RETURN = 0x003C0032,
    BASIC_DELIVER = 0x003C003C,
    BASIC_GET = 0x003C0046,
    BASIC_GET_OK = 0x003C0047,
    BASIC_GET_EMPTY = 0x003C0048,
    BASIC_ACK = 0x003C0050,
    BASIC_REJECT = 0x003C005A,
    BASIC_RECOVER_ASYNC = 0x003C0064,
    BASIC_RECOVER = 0x003C006E,
    BASIC_RECOVER_OK = 0x003C006F,
    BASIC_NACK = 0x003C0078,
    TX_SELECT = 0x005A000A,
    TX_SELECT_OK = 0x005A000B,
    TX_COMMIT = 0x005A0014,
    TX_COMMIT_OK = 0x005A0015,
    TX_ROLLBACK = 0x005A001E,
    TX_ROLLBACK_OK = 0x005A001F,
    CONFIRM_SELECT = 0x0055000A,
    CONFIRM_SELECT_OK = 0x0055000B,
    _,
};

// Messages

pub const channel_open_ok_t = extern struct {
    channel_id: bytes_t,
};

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

pub const connection_close_t = extern struct {
    reply_code: ReplyCode,
    reply_text: bytes_t,
    class_id: u16,
    method_id: u16,
};

pub const channel_close_t = extern struct {
    reply_code: ReplyCode,
    reply_text: bytes_t,
    class_id: u16,
    method_id: u16,
};
