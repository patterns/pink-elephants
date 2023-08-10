const std = @import("std");
const pkcs1 = @import("pkcs1");
const spin = @import("../spin/lib.zig");

const mem = std.mem;
const Allocator = mem.Allocator;
const b64 = std.base64.standard.Decoder;
const cert = std.crypto.Certificate;

pub const ProduceVerifierFn = *const fn (ally: Allocator, key_provider: []const u8) anyerror!ParsedVerifier;

// user defined step to harvest the verifier (pub key)
pub fn attachFetch(fetch: ProduceVerifierFn) void {
    // usually triggers network trip to the key provider:
    // - in wasi, we designate a proxy because it is one ACL rule
    // - on-premise, can be database retrieve,
    // - in tests, will short circuit (fake/hard-coded)
    produce = fetch;
}

// calculate SHA256 sum of signature base input str
pub fn sha256Base(rcv: anytype, sum: *[32]u8) !void {
    // SHA256 creates digests of 32 bytes.
    // (buffer at 512, may be up to 8192?)
    var buffer: [512]u8 = undefined;
    var chan = std.io.fixedBufferStream(&buffer);
    try impl.fmtBase(rcv, chan.writer());
    const base = chan.getWritten();

    //std.debug.print("base: {s}\x0A", .{base});
    std.crypto.hash.sha2.Sha256.hash(base, sum, .{});
}

// reconstruct the signature base input str
pub fn fmtBase(rcv: anytype, out: std.io.FixedBufferStream([]u8).Writer) !void {
    return impl.fmtBase(rcv, out);
}

// rewrite the host header
pub fn rewriteRule(pattern: []const u8, replace: []const u8) void {
    // for when the gateway (tunnel) is the public hostname and it forwards to
    // our internal server which has a different hostname
    // in other words, the host header will show as the internal server since
    // our wasm component receives the request on the internal server.
    // At the same time, the request has a HTTP signature created for the
    // public hostname.
    // TODO should this be managed as part of pre-processing in the life cycle
    //      (because if you look at the debug json payload saved to redis,
    //       we persist the headers)
    rewrite[0] = pattern;
    rewrite[1] = replace;
}

// verify signature
pub fn bySigner(ally: Allocator, base: []const u8) !bool {
    // _pre-verify_, harvest the public key
    impl.parsed = try produceVerifier(ally);

    return impl.bySigner(ally, base);
}

// allows test to fire the fetch event
pub fn produceVerifier(ally: Allocator) !ParsedVerifier {
    std.log.debug(">> produceV started\x0A", .{});

    if (impl.prev.getFirstValue("keyId")) |key_provider| {
        const clean = trimQuotes(key_provider);
        std.log.debug("keyId {s}\x0A", .{clean});
        return produce(ally, clean);
    } else {
        return error.LeafKeyprovider;
    }
}

// Reminder, _Verifier_ rename here is to emphasize that our concern is
// only the public key; at the same time, we are not making a general purpose
// public key, this verifier is limited to ActivityPub and the HTTP signature
// in Mastodon server crosstalk.
const Verifier = @This();
const Impl = struct { produce: ProduceVerifierFn };
var impl = ByRSASignerImpl{ .parsed = undefined, .prev = undefined, .ally = undefined };
var produce: ProduceVerifierFn = produceVanilla;
var rewrite: [2][]const u8 = [2][]const u8{ "", "" };

pub fn deinit() void {
    impl.deinit();
}
// preverify which uses std.http.Headers
// (to initialize auth params leaf nodes)
pub fn init(ally: Allocator, h2: std.http.Headers) !void {
    if (!h2.contains("signature")) return error.PreverifySignature;
    var p = std.http.Headers.init(ally);

    if (h2.getFirstValue("signature")) |root| {
        // from draft12Fields
        var start_index: usize = 0;
        while (std.mem.indexOfPos(u8, root, start_index, cm_codept)) |mark| {
            const tup = try leafOffsets(root, start_index, mark);
            try p.append(tup.fld, tup.val);
            start_index = mark + 1;
        }
        const end_mark = root.len;
        const end_tup = try leafOffsets(root, start_index, end_mark);
        try p.append(end_tup.fld, end_tup.val);
    }
    impl.prev = p;
    impl.ally = ally;
}
fn leafOffsets(root: []const u8, start_index: usize, mark: usize) !struct { fld: []const u8, val: []const u8 } {
    const f_start = start_index;
    const pos = std.mem.indexOfPos(u8, root, start_index, es_codept);
    if (pos == null) return error.SignatureLeafFormat;
    const f_len = pos.? - start_index;
    const v_start = pos.? + 1;
    const v_len = mark - v_start;
    const lookup = root[f_start..(f_start + f_len)];
    const val = root[v_start..(v_start + v_len)];
    return .{ .fld = lookup, .val = val };
}

const ByRSASignerImpl = struct {
    const Self = @This();
    parsed: ParsedVerifier,
    prev: std.http.Headers,
    ally: Allocator,

    fn deinit(self: *Self) void {
        self.prev.deinit();
        self.parsed.deinit(self.ally);
    }
    // reconstruct input-string
    fn fmtBase(
        self: Self,
        rcv: anytype,
        out: std.io.FixedBufferStream([]u8).Writer,
    ) !void {
        const verb: std.http.Method = rcv.method;
        const uri: []const u8 = rcv.uri;
        const h2: std.http.Headers = rcv.headers;

        // each signature subheader has its value encased in quotes
        const shd = self.prev.getFirstValue("headers");
        if (shd == null) return error.LeafHeaders;
        const recipe = trimQuotes(shd.?);
        var it = mem.tokenize(u8, recipe, sp_codept);

        const first = it.next();
        if (first == null) return error.SignatureDelim;

        // TODO double-check this, seen docs that begin with other subheaders
        if (!mem.startsWith(u8, first.?, "(request-target)")) {
            std.log.err("Httpsig leader format, {s}", .{first.?});
            return error.SignatureFormat;
        }
        var buffer: [8]u8 = undefined;
        const streq = std.ascii.eqlIgnoreCase;
        const verb_low = std.ascii.lowerString(&buffer, @tagName(verb));

        // base leader
        try out.print("{0s}: {1s} {2s}", .{ first.?, verb_low, uri });
        // base elements
        while (it.next()) |base_el| {
            if (streq("host", base_el)) {
                if (h2.getFirstValue("host")) |name| {
                    if (rewrite[0].len != 0 and streq(rewrite[0], name)) {
                        try out.print("{s}host: {s}", .{ lf_codept, rewrite[1] });
                    } else {
                        try out.print("{s}host: {s}", .{ lf_codept, name });
                    }
                }
            } else if (streq("date", base_el)) {
                //todo check timestamp
                if (h2.getFirstValue("date")) |date| {
                    try out.print("{s}date: {s}", .{ lf_codept, date });
                }
            } else if (streq("digest", base_el)) {
                //todo check digest
                if (h2.getFirstValue("digest")) |digest| {
                    try out.print("{s}digest: {s}", .{ lf_codept, digest });
                }
            } else {
                if (h2.getFirstValue(base_el)) |val| {
                    const lower = base_el;
                    try out.print("{s}{s}: {s}", .{ lf_codept, lower, val });
                }
            }
        }
    }

    // with the public key produced in preverify step, verify signature
    pub fn bySigner(self: Self, ally: Allocator, base: []const u8) !bool {
        std.log.debug(">> bySigner started\x0A", .{});
        std.log.debug("base {s}\x0A", .{base});
        // a RSA public key of modulus 2048 bits
        const rsa_modulus_2048 = 256;

        var buffer: [rsa_modulus_2048]u8 = undefined;
        var decoded = try self.signature(&buffer);
        // coerce to many pointer
        const c_decoded: [*]u8 = decoded.ptr;

        var hashed_msg: [32]u8 = undefined;
        ////const sha = cert.Algorithm.sha256WithRSAEncryption.Hash();
        ////sha.hash(base, &hashed_msg, .{});
        std.crypto.hash.sha2.Sha256.hash(base, &hashed_msg, .{});
        // coerce to many pointer
        const c_hashed: [*]u8 = &hashed_msg;

        var pkco = try cert.rsa.PublicKey.parseDer(self.parsed.bits());
        var modu: [rsa_modulus_2048]u8 = undefined;
        var expo: [3]u8 = undefined;
        std.mem.copy(u8, &modu, pkco.modulus);
        std.mem.copy(u8, &expo, pkco.exponent);
        var mo = std.fmt.bytesToHex(modu, .upper);
        var ex = std.fmt.bytesToHex(expo, .upper);
        var c_hex_mo: [:0]u8 = try ally.dupeZ(u8, &mo);
        var c_hex_ex: [:0]u8 = try ally.dupeZ(u8, &ex);
        defer ally.free(c_hex_mo);
        defer ally.free(c_hex_ex);

        std.log.debug(".. pkcs1.verify {s}, {s}\x0A", .{ c_hex_mo, c_hex_ex });
        // invoke verify from Mbed C/library
        try pkcs1.verify(c_hashed, c_decoded, c_hex_mo, c_hex_ex);

        return true;
    }

    fn signature(self: Self, buffer: []u8) ![]u8 {
        // signature is the leaf node from parsing in preverify step
        // which is base64 (format for header fields)

        if (self.prev.getFirstValue("signature")) |sig| {
            const clean = trimQuotes(sig);

            const max = try b64.calcSizeForSlice(clean);
            var decoded = buffer[0..max];
            try b64.decode(decoded, clean);
            return decoded;
        } else {
            return error.LeafSignature;
        }
    }
};

// mashup of Parsed from std
pub const ParsedVerifier = struct {
    const Self = @This();
    octet_string: []u8,
    algo: cert.Parsed.PubKeyAlgo,
    len: usize,

    // expose a convenience to the *bitstring* of pub key
    pub fn bits(self: Self) []const u8 {
        return self.octet_string[0..self.len];
    }
    //TODO pair to 'init'
    pub fn deinit(self: *Self, ally: Allocator) void {
        ally.free(self.octet_string);
    }
};

// pem: file stream of verifier
// out: buffer for storing parsed verifier
// returns slice which points to the buffer argument
pub fn fromPEM(
    ally: Allocator,
    pem: std.io.FixedBufferStream([]const u8).Reader,
    //out: []u8,
) !ParsedVerifier {
    const max = comptime maxPEM();
    var buffer: [max]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    var line_buf: [80]u8 = undefined;
    var begin_marker_found = false;
    while (try pem.readUntilDelimiterOrEof(&line_buf, lf_literal)) |line| {
        if (mem.startsWith(u8, line, "-----END ")) break;
        if (mem.startsWith(u8, line, "-----BEGIN ")) {
            // only care about public key
            if (mem.endsWith(u8, line, " PUBLIC KEY-----")) {
                begin_marker_found = true;
            }
            continue;
        }
        if (begin_marker_found) {
            _ = try fbs.write(line);
        }
    }

    const pubpem = fbs.getWritten();
    var der_bytes: [512]u8 = undefined;
    try b64.decode(&der_bytes, pubpem);

    // type-length-value begins 0x30 (sequence tag)
    if (der_bytes[0] != 0x30) return error.Asn1SequenceTag;
    const dere = cert.der.Element;
    const spki_el = try dere.parse(&der_bytes, 0);
    const algo_el = try dere.parse(&der_bytes, spki_el.slice.start);
    const bits_el = try dere.parse(&der_bytes, algo_el.slice.end);
    const cb = cert{ .buffer = &der_bytes, .index = undefined };
    const pub_key = try cert.parseBitString(cb, bits_el);

    // very common OID: 2a864886f70d010101
    // preceded by 0609 which means tag(06) and length(09)
    // also ending with 0500 which means tag(05) and null(00)

    const off2 = algo_el.slice.start + 1;
    const off3 = off2 + 1;

    const val2: usize = @intCast(der_bytes[off2]);
    const off4 = off3 + val2;
    const algo_cat = cert.AlgorithmCategory.map.get(der_bytes[off3..off4]);
    if (algo_cat == null) {
        std.log.warn("DER parse, pubkey algorithm unknown  ", .{});
        return error.UnknownAlgorithm;
    }
    var algo: cert.Parsed.PubKeyAlgo = undefined;
    switch (algo_cat.?) {
        .rsaEncryption => algo = .{ .rsaEncryption = {} },
        else => {
            // handle Ed25519 otherwise panic?
            std.log.warn("algo unknown", .{});
        },
    }

    // todo need a tagged union between Ed25519 / RSA pub
    const pub_slice = cb.buffer[pub_key.start..pub_key.end];
    ////const pk_components = try cert.rsa.PublicKey.parseDer(pub_slice);
    ////return try cert.rsa.PublicKey.fromBytes(pk_components.exponent, pk_components.modulus, ally);
    //std.log.warn("e {d}, n {any}", .{
    //    std.fmt.fmtSliceHexLower(pk_components.exponent),
    //    std.fmt.fmtSliceHexLower(pk_components.modulus),
    //});

    const pv_len = pub_key.end - pub_key.start;
    return ParsedVerifier{
        .octet_string = try ally.dupe(u8, pub_slice),
        .algo = algo,
        .len = pv_len,
    };
}

// initialization for the verifier fetch
fn produceVanilla(ally: Allocator, key_provider: []const u8) !ParsedVerifier {
    // todo should we fold in the custom fetch as a default (it requires conf settings)
    _ = ally;
    _ = key_provider;
    return error.FetchNotDefined;
}

// limit of RSA pub key
fn maxPEM() usize {
    // assume 4096 bits is largest RSA
    const count = 512;
    // base64 increases by 24 bits (or 4 x 6bit digits)
    const multi = 4;
    return count * multi;
}

fn trimQuotes(txt: []const u8) []const u8 {
    var clean = txt;
    if (mem.startsWith(u8, txt, escaped_quotes) or
        mem.endsWith(u8, txt, escaped_quotes))
    {
        // the backslash
        clean = mem.trim(u8, txt, escaped_quotes);
    }
    // bare quotation marks
    return mem.trim(u8, clean, qm_codept);
}

pub const VerifierError = error{
    ErrVerification,
    NotHashedBySHA256,
    FetchNotDefined,
    UnknownPEM,
    BufferMemByPEM,
    UnknownX509KeySpec,
    SignatureKeyId,
    SignatureAbsent,
    SignatureSequence,
    SignatureFormat,
    SignatureHost,
    SignatureDate,
    SignatureDigest,
    SignatureDecode,
};

const lf_codept = "\u{000A}";
const lf_literal = 0x0A;
const qm_codept = "\u{0022}";
const qm_literal = 0x22;
const sp_codept = "\u{0020}";
const sp_literal = 0x20;
const cm_codept = "\u{002C}";
const cm_literal = 0x2C;
const es_codept = "\u{003D}";
const es_literal = 0x3D;
const escaped_quotes = "\u{005C}\u{0022}";
