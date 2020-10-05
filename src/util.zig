const std = @import("std");

pub fn Bitset(comptime S: type) type {
    return struct {
        const Self = @This();
        pub const Elem = S;
        pub const Bits = std.meta.IntType(false, @typeInfo(S).Enum.fields.len);
        bits: Bits,

        pub const empty = Self{ .bits = 0 };

        pub fn singleton(elem: Elem) Self {
            return .{ .bits = @as(Bits, 1) << @enumToInt(elem) };
        }

        pub fn init_with(comptime elements: anytype) Self {
            var b = empty;
            inline for (elements) |elem| {
                b.set(@as(Elem, elem), true);
            }
            return b;
        }

        pub fn set(self: *Self, elem: Elem, val: bool) void {
            if (val)
                self.bits |= @as(Bits, 1) << @enumToInt(elem)
            else
                self.bits &= ~(@as(Bits, 1) << @enumToInt(elem));
        }

        pub fn get(self: *const Self, elem: Elem) bool {
            return self.bits & (@as(Bits, 1) << @enumToInt(elem)) != 0;
        }

        pub fn toggle(self: *Self, elem: Elem) void {
            self.bits ^= @as(Bits, 1) << @enumToInt(elem);
        }

        pub fn setAll(self: *Self, other: *const Self, val: bool) void {
            if (val)
                self.bits |= other.bits
            else
                self.bits &= ~other.bits;
        }

        pub fn any(self: *const Self, other: *const Self) bool {
            return self.bits & other.bits != 0;
        }

        pub fn all(self: *const Self, other: *const Self) bool {
            return self.bits & other.bits == other.bits;
        }
    };
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const Tag = enum { One, Two, Three };

test "init_with" {
    const TestSet = Bitset(Tag);

    const some = TestSet.init_with(.{ .Three, .One });
    const all = TestSet.init_with(.{ .One, .Two, .Three });
    const empty = TestSet.init_with(.{});

    expectEqual(some.bits, 0b101);
    expectEqual(all.bits, 0b111);
    expectEqual(empty.bits, 0b000);
}

test "single-element operations" {
    const TestSet = Bitset(Tag);

    var s = TestSet.empty;

    s.set(.One, true);
    expectEqual(s.bits, 0b001);
    s.set(.Three, false);
    expectEqual(s.bits, 0b001);
    s.toggle(.Two);
    expectEqual(s.bits, 0b011);
    s.toggle(.One);
    expectEqual(s.bits, 0b010);

    expect(!s.get(.Three));
    expect(s.get(.Two));
}

test "operations between sets" {
    const TestSet = Bitset(Tag);

    var s = TestSet.init_with(.{ .One, .Three });
    const t = TestSet.init_with(.{ .Two, .Three });

    s.setAll(&t, true);
    expectEqual(s.bits, 0b111);
    s.setAll(&t, false);
    expectEqual(s.bits, 0b001);
}
