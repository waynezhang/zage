const std = @import("std");

const clap = @import("clap");
const age = @import("age");

const fatal = std.zig.fatal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leak = gpa.deinit();
        std.debug.assert(leak == .ok);
    }

    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help                        Display this help and exit.
        \\-e, --encrypt                     Encrypt input to output, default.
        \\-d, --decrypt                     Decrypt input to output.
        \\-i, --identityfile <PATH>...      Encrypt/Decrypt using identity at path, can be repeated.
        \\-r, --recipient <STRING>...       Encrypt to recipient, can be repeated.
        \\-R, --recipientfile <PATH>...     Encrypt to recipients at path, can be repeated.
        \\-p, --passphrase                  Encrypt using passphrase.
        \\-o, --output <PATH>               Path to output file, default to stdout.
        \\<PATH>
        \\
    );

    const parsers = comptime .{
        .PATH = clap.parsers.string,
        .STRING = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    const args = res.args;

    const input = blk: {
        if (res.positionals.len == 0) {
            fatal("Missing input file.", .{});
        }
        const path = res.positionals[0];
        break :blk std.fs.cwd().openFile(path, .{}) catch |err| {
            fatal("Can't open file '{s}': {s}", .{ path, @errorName(err) });
        };
    };
    defer input.close();

    if (args.help != 0) {
        try clap.usage(std.io.getStdErr().writer(), clap.Help, &params);
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    if (args.encrypt != 0 and args.decrypt != 0) {
        std.debug.print("Can't encrypt and decrypt at the same time.", .{});
        return;
    }

    if (args.passphrase != 0 and (args.recipient.len != 0 or
        args.recipientfile.len != 0 or
        args.identityfile.len != 0))
    {
        std.debug.print("Passphrase can not be use in conjuction with recipient or identity.", .{});
        return;
    }

    if (args.decrypt != 0) {
        fatal("Not implemented.", .{});
    } else {
        var recipient: union(enum) {
            x25519: age.x25519.X25519Recipient,
            scrypt: age.scrypt.ScryptRecipient,
        } = undefined;

        if (args.recipientfile.len != 0) {
            fatal("Not implemented.", .{});
        }

        if (args.recipient.len > 1) {
            fatal("Not implemented.", .{});
        }

        if (args.recipient.len != 0) {
            for (args.recipient) |str| {
                recipient = .{ .x25519 = age.x25519.X25519Recipient.parse(allocator, str) catch |err| {
                    fatal("Failed to create recipient '{s}': {s}", .{ str, @errorName(err) });
                } };
            }
        } else if (args.passphrase != 0) {
            //TODO: secure way to get password from stdin
            const passphrase = "test";
            recipient = .{ .scrypt = try age.scrypt.ScryptRecipient.create(allocator, passphrase, null) };
        } else {
            fatal("Missing identity, recipient or passphrase.", .{});
        }

        const any_recipient: age.AnyRecipient = switch (recipient) {
            .scrypt => recipient.scrypt.any(),
            .x25519 => recipient.x25519.any(),
        };
        defer any_recipient.destroy();

        const buffer = try input.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(buffer);

        var encryptor = try age.AgeEncryptor.encryptInit(
            allocator,
            &.{any_recipient},
            std.io.getStdOut().writer().any(),
        );
        try encryptor.update(buffer);
        try encryptor.finish();
    }
}
