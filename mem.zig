const std = @import("std");

pub fn RefCounted(comptime T: type, comptime destroy: ?fn (referent: T) void) type {
    return struct {
        pub const Self = @This();

        const TaggedData = struct {
            allocator: std.mem.Allocator,
            data: T,
            destructor_opt: ?*const fn (referent: T) void,
            ref_count_ptr: *usize,
        };

        fn dummy_destroy(referent: T) void {
            _ = referent;
        }

        const destroy_fn = destroy orelse dummy_destroy;

        tagged_ref_ptr: ?*TaggedData,

        /// The `destructor` function is an optional function to be called on
        /// the referenced value immediately before deallocating the memory for
        /// it. If `null` is provided, then no function is called.
        pub fn init(alloc: std.mem.Allocator, destructor: ?*const fn (referent: T) void) !Self {
            const ref_count_ptr = try alloc.create(usize);
            errdefer alloc.destroy(ref_count_ptr);

            const tagged_data_ptr = try alloc.create(TaggedData);
            errdefer alloc.destroy(tagged_data_ptr);

            ref_count_ptr.* = 1;

            tagged_data_ptr.* = .{
                .allocator = alloc,
                .data = undefined,
                .destructor_opt = destructor,
                .ref_count_ptr = ref_count_ptr,
            };

            return .{
                .tagged_ref_ptr = tagged_data_ptr,
            };
        }

        pub fn decRef(self: *Self) !void {
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

        /// With a weak reference, there is no guarantee whether or when the
        /// referent will be deallocated. This could potentially lead to
        /// dereferencing a pointer to invalid memory if the caller is not
        /// careful with the pointer returned.
        pub fn weakRef(self: Self) ?*T {
            if (self.tagged_ref_ptr) |ref_ptr| {
                ref_ptr.ref_count_ptr.* += 1;
                return &ref_ptr.data;
            } else {
                return null;
            }
        }
    };
}

test {
    _ = RefCounted(usize, null);
}
