# deadcli
A simple one file zig library providing a easy to use command line interface.

## Why dead?
Simply I don't have infinite time to maintain what I write. So I strive for my code to be complete. Meaning I want it to be dead. But this involves it being extremely simple so don't expect many features but at least it won't be a giant codebase with a dozen of dependancies that can break or are insecure. 

## How to use it
1. In your `build.zig` add the following: (`exe` is your executable but can also be a library)
    ```zig
    const deadcliPackage = b.dependency("deadcli", .{
        .target = target,
        .optimize = optimize,
    });
    
    exe.root_module.addImport("deadcli", deadcliPackage.module("deadcli"));
    ```
2. Import the library either by used git submodule into `extern` and then adding 
    ```zig
    .deadsimple = .{
       .path = "extern/deadsimple",
    },
    ```
    to the `.dependencies` in `build.zig.zon` or be using zigs [inbuilt system](https://zig.news/edyu/zig-package-manager-wtf-is-zon-558e).
3. Example usage of the library on linux is as follows (with `const di = @import("deadcli");`):
    ```zig
    const stdoutFile = std.io.getStdOut().writer();

    const Args = di.ArgStruct(
        "exampleapp",
        "This is an example app.",
        &.{.{
            .name = "help",
            .desc = "Displays this help message.",
        }},
        &.{},
        &.{},
        null
    );

    const parsedArgs = Args.parseArgs(std.os.argv[1..]) catch {
        Args.displayHelp(stdout_file) catch @panic("stdout is inaccessible");
        return;
    };

    const args = parsedArgs.args;
    const rest = parsedArgs.remaining; // For remaining arguments after '-'

    if (args.help) {
        Args.displayHelp(stdout_file) catch @panic("stdout is inaccessible");
        return;
    }
    ```
    Note that `std.os.argv[1..]` may not work outside of linux. See zig docs for more info on how to get the arguments there.
