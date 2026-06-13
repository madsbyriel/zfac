const std = @import("std");
const Io = std.Io;
const zfac = @import("zfac");

const ArenaAllocator = std.heap.ArenaAllocator;
pub fn List(comptime T: type) type {
    return std.ArrayList(T);
}

const RandomAssStruct = struct {
    name: []const u8
};
var shared = RandomAssStruct{
    .name = "Mads!"
};

fn testttt() *RandomAssStruct {
    std.log.debug("TEST!!!!!", .{});
    return &shared;
}

const Container = struct {
    arena_allocator: *ArenaAllocator,
    contexts: List(Context),

    const Context = struct {
        return_type_name: []const u8,
        value: ?*anyopaque,
        // fn(ctx: *Context, container: *Container) void {
        callme: ?*const fn(*Context, *Container) void,
    };

    pub fn register(self: *Container, comptime func: anytype) !void {
        // comptime ----------------------------
        const Fn = @TypeOf(func);
        const fn_info: std.lang.Type = @typeInfo(Fn);
        switch (fn_info) {
            .@"fn" => {},
            else => @compileError("first argument must be a function"),
        }

        if (fn_info.@"fn".return_type == null)
            @compileError("function return type must be a pointer to struct");

        const ReturnType = fn_info.@"fn".return_type.?;
        const ret_type_info: std.lang.Type = @typeInfo(ReturnType);
        if (ReturnType == void)
            @compileError("function return type must be a pointer to struct");

        switch (ret_type_info) {
            .pointer => {},
            else => @compileError("function return type must be a pointer to struct"),
        }

        const PtrChildType = ret_type_info.pointer.child;
        const ptr_child_type_info: std.lang.Type = @typeInfo(PtrChildType);

        switch (ptr_child_type_info) {
            .@"struct" => {},
            else => @compileError("function return type must be a pointer to struct"),
        }

        comptime var param_types: [fn_info.@"fn".param_types.len]type = undefined;
        inline for (fn_info.@"fn".param_types, 0..) |ptype, i| {
            if (ptype == null)
                @compileError("function parameters must not be generic");

            const ptype_info: std.lang.Type = @typeInfo(ptype.?);
            switch (ptype_info) {
                .pointer => {},
                else => @compileError("param type must be pointer"),
            }

            const ptype_ptr_child_info: std.lang.Type = @typeInfo(ptype_info.pointer.child);
            switch (ptype_ptr_child_info) {
                .@"struct" => {},
                else => @compileError("Param types must be pointers to structs"),
            }
            param_types[i] = ptype.?;
        }

        // runtime -----------------------------
        const anon = struct {
            fn callme(ctx: *Context, container: *Container) void {
                var args: std.meta.ArgsTuple(Fn) = undefined;
                inline for (param_types, 0..) |ptype, i| {
                    const ptype_info: std.lang.Type = @typeInfo(ptype);
                    const val: ptype = container
                        .resolve(ptype_info.pointer.child) catch {
                        std.log.err("error calling something", .{});
                        return;
                    };
                    args[i] = val;
                }

                const v: ReturnType = @call(.auto, func, args);
                ctx.value = v;
            }
        };

        const ctx = Context{
            .return_type_name = @typeName(ReturnType),
            .value = null,
            .callme = anon.callme,
        };

        std.log.debug("registered: {s}", .{ctx.return_type_name});

        try self.contexts.append(self.arena_allocator.allocator(), ctx);
    }

    pub fn init(arena: *ArenaAllocator) !Container {
        var contexts = try List(Context).initCapacity(arena.allocator(), 0);

        try contexts.append(arena.allocator(), Context{
            .return_type_name = @typeName(*ArenaAllocator),
            .value = arena,
            // fn(ctx: *Context, container: *Container) void {
            .callme = null,
        });

        return Container{
            .arena_allocator = arena,
            .contexts = contexts,
        };
    }

    pub fn resolve(self: *Container, comptime T: type) !*T {
        const type_name: []const u8 = @typeName(*T);

        std.log.debug("finding constructor for {s}", .{type_name});
        var context: Context = try stuff: for (self.contexts.items) |ctx| {
            if (!std.mem.eql(u8, ctx.return_type_name, type_name))
                continue :stuff;

            std.log.debug(
                "found match {s} == {s}",
                .{type_name, ctx.return_type_name}
            );

            if (ctx.value != null)
                return @ptrCast(@alignCast(ctx.value.?));

            break :stuff ctx;
        } else error.NoConstructorFound;

        const f = context.callme;

        if (f == null)
            return error.ErrorConstructorNull;

        f.?(&context, self);

        if (context.value == null)
            return error.ErrorCreatingObject;

        return @ptrCast(@alignCast(context.value.?));
    }
};

pub fn main(init: std.process.Init) !void {
    var container = try Container.init(init.arena);
    try container.register(testttt);
    const s1 = try container.resolve(RandomAssStruct);
    const s2 = try container.resolve(RandomAssStruct);
    const s3 = try container.resolve(RandomAssStruct);
    const s4 = try container.resolve(RandomAssStruct);

    std.log.debug("received: {*}", .{s1});
    std.log.debug("received: {*}", .{s2});
    std.log.debug("received: {*}", .{s3});
    std.log.debug("received: {*}", .{s4});

    // const f: *anyopaque = @constCast(&testttt);
    // const actual_fn: *const fn (s: []const u8) void = @ptrCast(@alignCast(f));
    // @call(.auto, actual_fn, .{"mads"});
}
