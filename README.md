# deadsimple
A simple one file zig library providing a easy to use command line interface without needing allocations.

## CLI
This doesn't follow your typical syntax for switches and arguments as discribed [here](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html) but rather uses a much more simplified version as discribed in the following:
### Flags
Flags represent true or false. They default to false and are set true using `-flag` where `flag` is a name of a predefined flag.
### Optional Values
Optional Values are represented as strings. Internally they are of type `?[:0]const u8`. Empty values are not possible. They are set using `--option value` where `option` is a name of a predefined optional value and `value` will be the associated value.
### Positional Values
Positional Values are also represented as strings but internally as `[:0]const u8` meaning they have to be included otherwise the parsing fails. They are set using `value`. So simply writing the value. Its position in the arguments list isn't predefinied.
### Variadic Values
Variadic Values are a list of strings internally as `[]const [*:0]const u8`. They are set at the end after a single `-`. They are always accepted.
### Example
```
exampleapp -help test.csv --verbose 3 - 1 2 3 
```
Here we have the following:
1. `help` is set to true
2. `text.csv` is a positional value
3. `verbose` is set to `"3"`
4. Variadic Values contain `"1", "2", "3"`

## How to use it
1. In your `build.zig` add the following: (`exe` is your executable but can also be a library)
    ```zig
    const deadsimplePackage = b.dependency("deadsimple", .{
        .target = target,
        .optimize = optimize,
    });
    
    exe.root_module.addImport("deadsimple", deadsimplePackage.module("deadsimple"));
    ```
2. Import the library either by used git submodule into `extern` and then adding 
    ```zig
    .deadsimple = .{
       .path = "extern/deadsimple",
    },
    ```
    to the `.dependencies` in `build.zig.zon` or be using zigs [inbuilt system](https://zig.news/edyu/zig-package-manager-wtf-is-zon-558e).
3. Example usage of the library on linux is as follows (with `const cli = @import("deadsimple").cli;`):
    ```zig
    const stdoutFile = std.io.getStdOut().writer();

    const Args = cli.ArgStruct(
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
