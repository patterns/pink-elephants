const std = @import("std");

// C/host uses i32 as method which differ from std.http
pub fn rcvMethod(method: i32) std.http.Method {
    switch (method) {
        0 => return .GET,
        1 => return .POST,
        2 => return .PUT,
        3 => return .DELETE,
        4 => return .PATCH,
        5 => return .HEAD,
        6 => return .OPTIONS,
        else => unreachable,
    }
}

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
        const eq = std.ascii.eqlIgnoreCase;
        for (DescrTable, 0..) |row, rownum| {
            if (eq(row, text)) {
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
