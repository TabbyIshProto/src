const std = @import("std");
const spcftn = @import("specification.zig");
// imports

pub const eol = [_]u8{ '\n', '\r' };
pub const ident_delimiters = [_]u8{ '+', '-', '>', '<', '[', ']', '.', ',', '^', '#', '@', '=' };
// consts

pub fn contains(T: type, val: T, set: []const T) bool {
    for (set) |item| {
        if (item == val) return true;
    }
    return false;
}

pub const LexemeTag = enum { //add comments
    val,
    ident,
    comment,
    @"@", // return.
    @"=", // asignment.

    @"+",
    @"-",
    @">",
    @"<",
    openPar,
    closePar,
    @",",
    @".",

    @"^",
    v,

    eof,
    invalidette,
};

pub const Lexeme = struct {
    tag: LexemeTag,
    span: [2]usize,
};

pub const Lexer = struct {
    source: []const u8,
    loc: usize = 0,
    peek: ?Lexeme = null,

    // a list of ints storing letters by bit possitional notation, twice per bit to indicate the beginning and end of an ident, fill_scr is saved as f and r in possitional notation
    // aka 00000000 00000010 00000000 00100000  OR all letters that are contained within, like so vv
    //     00000100 00000110 00001001 00100100
    //          _zy xwvutsrq ponmlkji hgfedcba

    pub const LxrState = enum {
        default,
        ident,
    }; // 0 1 2 3 4, len = 5

    fn check(src: []const u8, loc: usize) ?usize { // ff7f
        const lim = @min(spcftn.int_size >> 2, src.len - loc);
        return loc + for (0..lim) |jdex| {
            if (std.ascii.isWhitespace(src[loc + jdex])) break jdex;
            if (!contains(u8, src[loc + jdex], "1234567890abcdef")) return null;
        } else lim;
    }

    pub fn create(source: []const u8) Lexer {
        return Lexer{ .source = source };
    }

    pub fn next(self: *Lexer) Lexeme {
        const src = self.source;
        if (self.peek) |token| {
            self.peek = null;
            return token;
        }

        const next_loc = std.mem.indexOfNonePos(u8, src, self.loc, &std.ascii.whitespace) orelse
            return Lexeme{ .tag = .eof, .span = .{ src.len, src.len } };

        const char = src[next_loc];
        const tag = switch (char) {
            '#' => return Lexeme{ .tag = .comment, .span = find(.until, &eol ++ [1]u8{'#'}, self, next_loc) },
            'a'...'f', 'g'...'u', 'w'...'z', 'A'...'Z', '_' => {
                const is_val: ?usize = check(src, next_loc);
                if (is_val) |val| {
                    self.loc = val;
                    return Lexeme{ .tag = .val, .span = .{ next_loc, val } };
                }

                const limit = next_loc + @min(spcftn.ident_char_cap, src.len - next_loc); //was not checking for a limit but instead loc + limit, always picking the option of "until the end"
                var delimiter_loc = next_loc + std.mem.indexOfAnyPos(u8, src[next_loc..limit], 0, &std.ascii.whitespace ++ ident_delimiters).?;
                if (!std.ascii.isWhitespace(src[delimiter_loc])) while (src[delimiter_loc - 1] == 'v') : (delimiter_loc -= 1) {};
                if (delimiter_loc - (spcftn.int_size >> 2) < next_loc) {}
                self.loc = delimiter_loc;
                return Lexeme{ .tag = .ident, .span = .{ next_loc, delimiter_loc } };
            },
            // if its any non 0-f or v char then guaranteed ident
            // 0 - 9 guaranteed num
            // g - z A - Z _ [minus v] guaranteed ident
            // a-f and v are edge cases
            '0'...'9' => {
                const digits = "1234567890abcdef";
                return Lexeme{ .tag = .val, .span = find(.range, digits, self, next_loc) };
            },
            '+', '-', '>', '<', '^', 'v' => {
                const caller_char: []const u8 = &[1]u8{char};
                return Lexeme{
                    .tag = get(caller_char[0]), // slice because of vv func
                    .span = find(.range, caller_char, self, next_loc),
                };
            },
            '[' => LexemeTag.openPar,
            ']' => LexemeTag.closePar,
            '@' => LexemeTag.@"@",

            ',', '.', '=' => blk: {
                //self.state = .ident;
                break :blk get(char);
            },
            else => LexemeTag.invalidette, // add switch between invalidette & just {}
        };
        self.loc = next_loc + 1;
        const res = Lexeme{ .tag = tag, .span = .{ next_loc, next_loc + 1 } };
        return res;
    }

    pub fn undo(self: *Lexer, lxm: Lexeme) void {
        std.debug.assert(self.peek == null);
        self.peek = lxm;
    }

    fn find(plr: Polarity, vals: []const u8, self: *Lexer, loc: usize) [2]usize {
        const diff = switch (plr) {
            .range => std.mem.indexOfNonePos(u8, self.source, loc + 1, vals) orelse self.source.len,
            .until => std.mem.indexOfAnyPos(u8, self.source, loc + 1, vals) orelse self.source.len,
        };
        self.loc = diff;
        return .{ loc, diff };
    }

    const Polarity = enum {
        range,
        until,
    };

    fn get(char: u8) LexemeTag {
        return switch (char) {
            '+' => LexemeTag.@"+",
            '-' => LexemeTag.@"-",
            '>' => LexemeTag.@">",
            '<' => LexemeTag.@"<",

            '^' => LexemeTag.@"^",
            'v' => LexemeTag.v,

            ',' => LexemeTag.@",",
            '.' => LexemeTag.@".",
            '=' => LexemeTag.@"=",
            else => LexemeTag.invalidette,
        };
    }
};

test "lexer" {
    //nothing here yet :P
    const source = @embedFile("test-Programs/tok-test.bf");
    var tokeniser = Lexer.create(source);

    for ([_]Lexeme{
        .{ .tag = .@"+", .span = .{ 0, 1 } },
        .{ .tag = .val, .span = .{ 1, 4 } },
        .{ .tag = .openPar, .span = .{ 6, 7 } },
        .{ .tag = .@"-", .span = .{ 7, 8 } },
        .{ .tag = .@".", .span = .{ 8, 9 } },
        .{ .tag = .ident, .span = .{ 9, 14 } },
        .{ .tag = .v, .span = .{ 14, 15 } },
        .{ .tag = .@"+", .span = .{ 15, 16 } },
        .{ .tag = .closePar, .span = .{ 16, 17 } },
        .{ .tag = .comment, .span = .{ 19, 67 } },

        .{ .tag = .eof, .span = .{ 69, 69 } },
    }) |expected| {
        try std.testing.expectEqual(expected, tokeniser.next());
    }
} //ff7
//[-.numvav+]
// making changes here doesn't magically mean they change over in tok-test.bf

test "lexer-out" {
    const souy = "ff7f";
    var tokeniser = Lexer.create(souy);
    comptime var i = 0;
    inline while (true) : (i += 1) {
        const token = tokeniser.next();
        std.debug.print("{}\n", .{token});
        if (token.tag == .eof or i > 20) break;
    }
}
