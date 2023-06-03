const std = @import("std");
const pkcs1 = @import("pkcs1");

const spin = @import("../spin/lib.zig");
const phi = @import("../web/phi.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;
const b64 = std.base64.standard.Decoder;
const streq = std.ascii.eqlIgnoreCase;
const cert = std.crypto.Certificate;
const dere = cert.der.Element;

pub const ProduceVerifierFn = *const fn (ally: Allocator, key_provider: []const u8) anyerror!ParsedVerifier;

// user defined step to harvest the verifier (pub key)
pub fn attachFetch(fetch: ProduceVerifierFn) void {
    // usually triggers network trip to the key provider:
    // - in wasi, we designate a proxy because no ACL will be exhaustive
    // - on-premise, can be database retrieve,
    // - in tests, will short circuit (fake/hard-coded)
    produce = fetch;
}

// calculate SHA256 sum of signature base input str
pub fn sha256Base(req: spin.Request, headers: phi.HeaderList) ![sha256_len]u8 {
    var buffer: [sha256_len]u8 = undefined;
    const base = try impl.fmtBase(@intToEnum(Verb, req.method), req.uri, headers);
    std.crypto.hash.sha2.Sha256.hash(base, &buffer, .{});
    return buffer;
}

// reconstruct the signature base input str
pub fn fmtBase(req: spin.Request, headers: phi.HeaderList) ![]const u8 {
    return impl.fmtBase(@intToEnum(Verb, req.method), req.uri, headers);
}
pub fn fmtBase2(req: spin.Request, h2: std.http.Headers) ![]const u8 {
    return impl.fmtBase2(@intToEnum(Verb, req.method), req.uri, h2);
}

// verify signature
pub fn bySigner(ally: Allocator, base: []const u8) !bool {
    // _pre-verify_, harvest the public key
    impl.parsed = try produceVerifier(ally);

    return impl.bySigner(ally, base);
}

// allows test to fire the fetch event
pub fn produceVerifier(ally: Allocator) !ParsedVerifier {
    if (produce != undefined) {
        const key_provider = impl.auth.get(.sub_key_id).value;
        const clean = std.mem.trim(u8, key_provider, "\"");
        return produce(ally, clean);
    }
    return error.FetchNotDefined;
}

// sprout related preverify which uses std.http.Headers
// (to initialize auth params list)
pub fn prev2(ally: Allocator, h2: std.http.Headers) !void {
    if (!h2.contains("signature")) return error.PreverifySignature;
    var p = std.http.Headers.init(ally);
    if (h2.getFirstValue("signature")) |root| {
        // from draft12Fields
        var start_index: usize = 0;
        while (std.mem.indexOfPos(u8, root, start_index, ",")) |mark| {
            const tup = try leafOffsets(root, start_index, mark);
            try p.append(tup.fld, tup.val);
            start_index = mark + 1;
        }
        const end_mark = root.len;
        const end_tup = try leafOffsets(root, start_index, end_mark);
        try p.append(end_tup.fld, end_tup.val);
    }
    impl.prev = p;
}
fn leafOffsets(root: []const u8, start_index: usize, mark: usize) !struct { fld: []const u8, val: []const u8 } {
    const f_start = start_index;
    const pos = std.mem.indexOfPos(u8, root, start_index, "=");
    if (pos == null) return error.SignatureLeafFormat;
    const f_len = pos.? - start_index;
    const v_start = pos.? + 1;
    const v_len = mark - v_start;
    const lookup = root[f_start..(f_start + f_len)];
    const val = root[v_start..(v_start + v_len)];
    return .{ .fld = lookup, .val = val };
}

// Reminder, _Verifier_ rename here is to emphasize that our concern is
// only the public key; at the same time, we are not making a general purpose
// public key, this verifier is limited to ActivityPub and the HTTP signature
// in Mastodon server crosstalk.
const Verifier = @This();
const Impl = struct { produce: ProduceVerifierFn };
var impl = ByRSASignerImpl{ .auth = undefined, .parsed = undefined, .prev = undefined };
var produce: ProduceVerifierFn = undefined;

pub fn init(ally: Allocator, raw: phi.RawHeaders) !void {
    impl.auth = phi.AuthParams.init(ally, raw);
    try impl.auth.preverify();
}

const ByRSASignerImpl = struct {
    const Self = @This();

    auth: phi.AuthParams,
    parsed: ParsedVerifier,
    prev: std.http.Headers,

    // reconstruct input-string
    pub fn fmtBase(
        self: Self,
        verb: Verb,
        uri: []const u8,
        headers: phi.HeaderList,
    ) ![]const u8 {
        // each signature subheader has its value encased in quotes
        const shd = self.auth.get(.sub_headers).value;
        const recipe = mem.trim(u8, shd, "\"");
        var it = mem.tokenize(u8, recipe, " ");

        const first = it.next();
        if (first == null) return error.SignatureDelim;

        // TODO double-check this, seen docs that begin with other subheaders
        if (!mem.startsWith(u8, first.?, "(request-target)")) {
            log.err("Httpsig leader format, {s}", .{first.?});
            return error.SignatureFormat;
        }

        // prep bucket for base elements (multiline)
        var acc: [512]u8 = undefined;
        var chan = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(&acc) };
        var out = chan.writer();

        // base leader
        try out.print("{0s}: {1s} {2s}", .{ first.?, verb.toDescr(), uri });
        // base elements
        while (it.next()) |base_el| {
            if (streq("host", base_el)) {
                const name = headers.get(.host).value;
                try out.print("{s}host: {s}", .{ lf_codept, name });
            } else if (streq("date", base_el)) {
                //todo check timestamp
                const date = headers.get(.date).value;
                try out.print("{s}date: {s}", .{ lf_codept, date });
            } else if (streq("digest", base_el)) {
                //todo check digest
                const digest = headers.get(.digest).value;
                try out.print("{s}digest: {s}", .{ lf_codept, digest });
            } else {
                // TODO handle USER-DEFINED
                const kind = phi.Kind.fromDescr(base_el);
                const val = headers.get(kind).value;

                const lower = base_el;
                try out.print("{s}{s}: {s}", .{ lf_codept, lower, val });
            }
        }

        return chan.buffer.getWritten();
    }
    pub fn fmtBase2(
        self: Self,
        verb: Verb,
        uri: []const u8,
        h2: std.http.Headers,
    ) ![]const u8 {
        // each signature subheader has its value encased in quotes
        const shd = self.prev.getFirstValue("headers");
        if (shd == null) return error.LeafHeaders;
        const recipe = mem.trim(u8, shd.?, "\"");
        var it = mem.tokenize(u8, recipe, " ");

        const first = it.next();
        if (first == null) return error.SignatureDelim;

        // TODO double-check this, seen docs that begin with other subheaders
        if (!mem.startsWith(u8, first.?, "(request-target)")) {
            log.err("Httpsig leader format, {s}", .{first.?});
            return error.SignatureFormat;
        }

        // prep bucket for base elements (multiline)
        var acc: [512]u8 = undefined;
        var chan = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(&acc) };
        var out = chan.writer();

        // base leader
        try out.print("{0s}: {1s} {2s}", .{ first.?, verb.toDescr(), uri });
        // base elements
        while (it.next()) |base_el| {
            if (streq("host", base_el)) {
                if (h2.getFirstValue("host")) |name| {
                    try out.print("{s}host: {s}", .{ lf_codept, name });
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

        return chan.buffer.getWritten();
    }

    // verify signature
    pub fn bySigner(self: Self, ally: Allocator, base: []const u8) !bool {
        // a RSA public key of modulus 2048 bits
        const rsa_modulus_2048 = 256;

        var decoded: [rsa_modulus_2048]u8 = undefined;
        _ = try self.signature(&decoded);
        // coerce to many pointer
        const c_decoded: [*]u8 = &decoded;

        var hashed_msg: [32]u8 = undefined;
        const sha = cert.Algorithm.sha256WithRSAEncryption.Hash();
        sha.hash(base, &hashed_msg, .{});
        // coerce to many pointer
        const c_hashed: [*]u8 = &hashed_msg;

        const pkco = try cert.rsa.PublicKey.parseDer(self.parsed.bits());
        const c_mod: [:0]u8 = try ally.dupeZ(u8, pkco.modulus);
        const c_exp: [:0]u8 = try ally.dupeZ(u8, pkco.exponent);
        defer ally.free(c_mod);
        defer ally.free(c_exp);
        std.debug.print("\n?,mo: {s}", .{std.fmt.fmtSliceHexLower(c_mod)});
        std.debug.print("\n?,ex: {s}", .{std.fmt.fmtSliceHexLower(c_exp)});

        // invoke verify from Mbed C/library
        try pkcs1.verify(c_hashed, c_decoded, c_mod, c_exp);

        return true;
    }

    fn signature(self: Self, buffer: []u8) ![]u8 {
        // signature comes from the auth params list
        // which is base64 (format for header fields)

        const sig = self.auth.get(.sub_signature).value;
        const clean = mem.trim(u8, sig, "\"");
        const max = try b64.calcSizeForSlice(clean);

        var decoded = buffer[0..max];
        try b64.decode(decoded, clean);
        return decoded;
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

    const val2 = @intCast(usize, der_bytes[off2]);
    const off4 = off3 + val2;
    const algo_cat = cert.AlgorithmCategory.map.get(der_bytes[off3..off4]);
    if (algo_cat == null) {
        log.warn("DER parse, pubkey algorithm unknown  ", .{});
        return error.UnknownAlgorithm;
    }
    var algo: cert.Parsed.PubKeyAlgo = undefined;
    switch (algo_cat.?) {
        .rsaEncryption => algo = .{ .rsaEncryption = {} },
        else => {
            // handle Ed25519 otherwise panic?
            log.warn("algo unknown", .{});
        },
    }

    // todo need a tagged union between Ed25519 / RSA pub
    const pub_slice = cb.buffer[pub_key.start..pub_key.end];
    ////const pk_components = try cert.rsa.PublicKey.parseDer(pub_slice);
    ////return try cert.rsa.PublicKey.fromBytes(pk_components.exponent, pk_components.modulus, ally);
    //log.warn("e {d}, n {any}", .{
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

// SHA256 creates digests of 32 bytes.
const sha256_len: usize = 32;

// limit of RSA pub key
fn maxPEM() usize {
    // assume 4096 bits is largest RSA
    const count = 512;
    // base64 increases by 24 bits (or 4 x 6bit digits)
    const multi = 4;
    return count * multi;
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

// http method / verbs (TODO don't expose publicly if possible)
pub const Verb = enum(u8) {
    get = 0,
    post = 1,
    put = 2,
    delete = 3,
    patch = 4,
    head = 5,
    options = 6,

    // description (name) format of the enum
    pub fn toDescr(self: Verb) [:0]const u8 {
        //return DescrTable[@enumToInt(self)];
        // insted of table, switch
        switch (self) {
            .get => return "get",
            .post => return "post",
            .put => return "put",
            .delete => return "delete",
            .patch => return "patch",
            .head => return "head",
            .options => return "options",
        }
    }

    // convert to enum
    pub fn fromDescr(text: []const u8) Verb {
        for (DescrTable, 0..) |row, rownum| {
            if (streq(row, text)) {
                return @intToEnum(Verb, rownum);
            }
        }
        unreachable;
    }
    // TODO remove the table in favor of switch
    // lookup table with the description
    pub const DescrTable = [@typeInfo(Verb).Enum.fields.len][:0]const u8{
        "get",
        "post",
        "put",
        "delete",
        "patch",
        "head",
        "options",
    };
};

const lf_codept = "\u{000A}";
const lf_literal = 0x0A;
