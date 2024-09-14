const std = @import("std");

/// Basic reference counted generic type.
///
/// Weak reference support is minimal: it just returns a raw pointer to the
/// variable stored in the reference. Without care it is easy to shoot oneself
/// in the foot with a weak reference by deferencing invalid memory. Take care
/// when using a weak reference.
///
/// Currently requires that the instances be mutable for decrementing the
/// count, since it will turn the internal pointer into `null` on the last
/// reference object decremented. This makes it safer to deal with a refcount
/// instance that may stay around after decrementing, since it will just return
/// null optionals for everything requested. However, it means that this cannot
/// be used in a context that is constant.
///
/// Class is roughly inspired/based on the code found here:
/// https://github.com/ziglang/zig/issues/453#issuecomment-328309269
pub fn RefCounted(comptime T: type) type {
    return struct {
        pub const Self = @This();

        const TaggedData = struct {
            allocator: std.mem.Allocator,
            data: T,
            destructor_opt: ?*const fn (referent: T) void,
            ref_count_ptr: *usize,
        };

        tagged_ref_ptr: ?*TaggedData,

        /// If `initial_value` is `null` , the initial value will just be
        /// `undefined`. The only place this is an issue is when the type `T`
        /// is an optional type; in that case, the value will need to be
        /// explicitly set after init using a weakRef pointer.
        ///
        /// The `destructor` function is an optional function to be called on
        /// the referenced value immediately before deallocating the memory for
        /// it. If `null` is provided, then no function is called.
        pub fn initRef(alloc: std.mem.Allocator, initial_value: ?T, destructor: ?*const fn (referent: T) void) !Self {
            const ref_count_ptr = try alloc.create(usize);
            errdefer alloc.destroy(ref_count_ptr);

            const tagged_data_ptr = try alloc.create(TaggedData);
            errdefer alloc.destroy(tagged_data_ptr);

            ref_count_ptr.* = 1;

            tagged_data_ptr.* = .{
                .allocator = alloc,
                .data = initial_value orelse undefined,
                .destructor_opt = destructor,
                .ref_count_ptr = ref_count_ptr,
            };

            return .{
                .tagged_ref_ptr = tagged_data_ptr,
            };
        }

        pub fn refCount(self: Self) usize {
            return if (self.tagged_ref_ptr) |ref_ptr| ref_ptr.ref_count_ptr.* else 0;
        }

        pub fn decRef(self: *Self) void {
            if (self.tagged_ref_ptr) |ref_ptr| {
                ref_ptr.ref_count_ptr.* -= 1;
                if (ref_ptr.ref_count_ptr.* == 0) {
                    const alloc = ref_ptr.allocator;
                    const ref_count_ptr = ref_ptr.ref_count_ptr;

                    if (ref_ptr.destructor_opt) |destructor| {
                        destructor(ref_ptr.data);
                    }

                    alloc.destroy(ref_ptr);
                    alloc.destroy(ref_count_ptr);

                    self.tagged_ref_ptr = null;
                }
            }
        }

        pub fn strongRef(self: Self) ?Self {
            if (self.tagged_ref_ptr) |ref_ptr| {
                ref_ptr.ref_count_ptr.* += 1;
                return .{ .tagged_ref_ptr = ref_ptr };
            } else {
                return null;
            }
        }

        /// A weak references is just an unnaccounted for raw pointer.
        ///
        /// Thus with a weak reference,
        /// there is no guarantee whether or when the referent will be deallocated.
        /// This could potentially lead to dereferencing a pointer to invalid memory
        /// if the caller is not careful with the pointer returned.
        pub fn weakRef(self: Self) ?*T {
            return if (self.tagged_ref_ptr) |ref_ptr| &ref_ptr.data else null;
        }
    };
}

test {
    const alloc = std.testing.allocator;
    var usize_ref = try RefCounted(usize).initRef(alloc, 5, null);
    defer usize_ref.decRef();

    try std.testing.expectEqual(1, usize_ref.refCount());

    const usize_ptr = usize_ref.weakRef() orelse unreachable;
    try std.testing.expectEqual(5, usize_ptr.*);

    usize_ptr.* += 1;

    var usize_ref2 = usize_ref.strongRef() orelse unreachable;
    defer usize_ref2.decRef();

    const usize_ptr2 = usize_ref2.weakRef() orelse unreachable;
    try std.testing.expectEqual(6, usize_ptr2.*);

    try std.testing.expectEqual(2, usize_ref2.refCount());
    try std.testing.expectEqual(usize_ref.refCount(), usize_ref2.refCount());
}
