FA reads configuration information only from FA.INI (unlike ARC.EXE that reads all ARC\*.INI files), that should be placed to the same directory as FA executable. FA.INI has exactly the same structure as ARC.INI, plus allows to write Lua code in sections with headings `[Lua code*]`.

FA contains builtin configuration file that you can display with `fa --print-config`. Its `[Lua code]` section provides [[examples|0.11/Builtin-Lua-option-definitions.md]] of options defined with Lua code. As of FA 0.11, `11 of 45` options are defined in Lua, including 100-line long `-mc` implementation.

* [What you can do with Lua code](#code)  
* [Handling the compression method](#compression-method)  
* [Defining event handlers](#events)  
* [File filtering](#file-filtering)  
* [Handling program options](#options)  
  * [High-level way of option definition](#options-high-level)  
  * [Mid-level way of option definition](#options-mid-level)  
  * [Low-level way: handling Option and PostOption events](#options-low-level)  
  * [Parsing order](#options-order)  
  * [Parsing algorithm](#options-parsing-algorithm)  


<a name="code"/>

## What you can do with Lua code

Lua code provided in config file is executed at the program start, right after executing builtin Lua code, and has access to the following resources:

* all built-in Lua functions plus a few functions defined by the [[builtin Lua code|0.11/Builtin-Lua-startup-code.md]]
* read/write access to values of C++ options as pseudo-fields of the `command` table
* read/write access to values of Lua options as fields of the `optvalue` table
* services provided by C++ code

"C++ options" and "Lua options" refer to options defined by C++ and Lua code, respectively.

You can use Lua code to:
* modify [compression method](#compression-method)
* [register event handlers](#events) that will be raised on various events
* [register new options](#options) and modify/remove existing ones

I plan to further extend Lua scripting support with:
* handling all the user interaction (UI, logfile) via Lua events
* filename transformation events that can be used to implement -ap/-dp/-ep/...
* Lua events to detect type of file data, sort the files being archived and split them into solid blocks
* provide general archive operation that can add/extract/rename/delete files with multiple source and destination archives and use Lua functions to limit this general operation to the add/update/extract/delete/join ones


Pseudo-fields of the `command` table:
* cmd - command name (a,add,x...)
* arcname - archive name as specified at the command line
* filenames - filenames specified in the command line (contents of listfiles is substituted instead of `@listfile` items)
* [[other pseudofields providing read/write access to values of corresponding C++ options|0.11/Builtin-CPP-option-definitions.md#fields]]


Services provided by C++ code:
* FA_VERSION() returns FA version number as string, f.e. "0.11"
* GetCpuThreads() is a number of threads that may run simultaneously on this box
* GetPhysicalMemory() is a total RAM size, in bytes
* GetAvailablePhysicalMemory() is a current free RAM size, in bytes
* GetGlobalTime() returns wall-clock time in seconds since some moment
* GetCpuTime() returns number of seconds spent in this process
* SetLargePageMode(mode) sets the large page mode to one of: "DEFAULT", "TRY", "FORCE", "DISABLE", "MALLOC"
* command.AllocTopDown is a boolean variable, true = allocate large memory blocks in BigAlloc() starting from memory top


<a name="compression-method"/>

## Handling the compression method

Compression method is encoded by two pseudo-fields of `command`:
* `compression_groups` contains list of group names such as "$text", "$bmp" and so
* `compression_methods` contains corresponding sequences of compression methods, such as "exe+lzma:1g"

They are filled at the start of option post-processing with values determined from options implemented in C++. For example, for `-m1` compression method, their values will be:

```lua
command.compression_groups = {'', '$compressed'}
command.compression_methods = {'rep:96mb:256:c256+4x4:tor:3:8mb', 'rep:96mb:256:c256'}
```

Since the arrays are synchronized, their lengths will be the same. At the end of option post-processing, their lengths also should be the same, while in-between you can change them in any way. It's strongly recommended to copy their values into local variables and assign final values at the end of processing, due to limited support of C++ variables in Lua.

You can modify these variables to change the compression method. Some examples of functions that you can employ for this task:

```lua
print (GetCompressionMem("lzma:1g:max") / 1e9 .. ' GB')
print (SetCompressionMem("lzma:1g:max",1e9))
print (GetMaxCompressedSize("lzma", 1e9))
onPostOption (function ()
    print (DecodeMethod("exe2+4xb"))
end)
```

`DecodeMethod` expands abbreviated name of compressor or sequence of compressors with substitutions provided in `[Compression methods]` config sections. For example `DecodeMethod('exe2+4xb') == 'dispack070+delta+4x4:lzma:96mb:normal:16:mc8'`. The function isn't available until all options are parsed (i.e. you can use it only on option post-processing stage or later).

Getter methods return a number representing some size in bytes:
* `GetCompressionMem(method)` - memory required for compression using given `method`
* `GetMinCompressionMem(method)` - the same for method modified with `:t1:i0` settings (can make the difference for 
`4x4` and `grzip` methods)
* `GetDecompressionMem(method)` - memory required for decompression
* `GetMinDecompressionMem(method)` - the same for method modified with `:t1:i0` settings
* `GetDictionary(method)` - dictionary (i.e. how far compressor looks searching for similar data)
* `GetBlockSize(method)` - block size, i.e. how much data is meaningful to place in the single solid block (for BlockSorting algorithms and my LZP/Dict implementations)
* `GetAlgoMem(method)` - "characteristic" memory size of algorithm (used only for displaying to user)
* `GetMaxCompressedSize(method,input_size)` - maximum possible compressed size for given `input_size` when using this `method`. Note that result may depend on method settings, f.e. results for `tor:1` and `tor:5` will be different.
* `CompressionService(method, service, param=0)` - generic function requesting info about the compression method, see `doit()` implementations for possible `service` values; the result is always numeric, f.e. `CompressionService("aes", "encryption?")` returns 1. If `method` doesn't implement the requested `service`, FREEARC_ERRCODE_NOT_IMPLEMENTED == -8 will be returned.

Setter methods return string with modified method:
* `SetDictionary(method,BYTES)` - set method dictionary
* `SetBlockSize(method,BYTES)` - set compression block size
* `SetCompressionMem(method,BYTES)` - modify method so that it uses given amount of RAM for compression
* `SetDecompressionMem(method,BYTES)` - modify method so that it uses given amount of RAM for extraction. It may be used on extraction since it modifies method without losing compatibility with compressed data. This setter can only reduce number of additional threads and buffers used for decompression. Current implementation can reduce `4x4` and `grzip` settings up to `:t1:i0`, but can't modify any other compression methods.
* `SetMinDecompressionMem(method,BYTES)` - modify method so that it can be extracted using given amount of RAM, possibly with limited speed (i.e. using `:t1:i0` setting for `4x4` and `grzip`). It should be used only on compression stage since it can return method incompatible with original. This function can reduce dictionary, block size and so on.
* `CompressionModify(method, service, param)` - generic function for modification of compression method, see `doit()` implementations for possible `service` values. The `method` will return unchanged if it doesn't implement the requested `service`.

If some concept (i.e. dictionary or block size) isn't supported by given algorithm, getter methods will return 0, and setter methods will return original method. Note that setters can modify method string since it always goes through the parsing and pretty-printing transfromations.

Also note that `compression_methods` contains compressor sequence strings like "exe+lzma:1g", for processing with getters and setters you need to split them into individual methods with `split_method` and then combine back with `join_method`.

These functions are enough to implement options -lc, -ld, -md, -mm, -ms. You can learn how to deal with compression method looking at [[-mc implementation|0.11/Builtin-Lua-option-definitions.md]].


<a name="events"/>

## Registering event handlers

Example of event handler registration:

```lua
onArchiveStart(function ()
    print("Started processing of "..command.arcname)
end)
```

You can register handlers for the following events:
* ProgramStart/ProgramDone - fired once at the start and end of program execution
* CommandStart/CommandDone - fired for each command executed
* ArchiveStart/ArchiveDone - fired for each archive processed
* Option/PostOption - implements [low-level option processing](#options-low-level)
* FileFilter - low-level interface for [filtering files to process](#file-filtering)
* Error and Warning - fired when program encounters error or should produce a warning. Not implemented yet.

Instead of function, you can provide a string with its textual representation, it may be useful for handlers generated from the user input:
```lua
onArchiveStart([[function ()
    print("Started processing of "..command.arcname)
end]])
```

Each event is handled by calling Lua function with the same name. Built-in definitions of these functions just run all handlers registered with corresponding `onXXX` calls - until one of the handlers returns non-nil result that is then returned to C++ as an result of the entire event. If you will ever need more complex event handling machinery, you can replace builtin definitions with your custom ones:

```lua
-- Replace builtin definiton of ArchiveStart()
function ArchiveStart()
    print("Started processing of "..command.arcname)
    print("Handlers registered with onArchiveStart will not be called")
end
```

<a name="file-filtering"/>

## File filtering

On compression operation, the program scans disk looking for files to compress. On extraction operation (as well as listing and testing), the program scans archive looking for files to extract. In both cases, all the files found (either on disk or in the archive) are checked against handlers registered for the `FileFilter` event - the file will be included in operation only if all handlers returned `true` for that file.

Handler example:
```lua
onFileFilter (function (name, type, size, time, attr)
    return size < 1024
end)
```

As you see, `FileFilter` handler receives information about the file - path-stripped filename, filesize, file creation time, and windows/unix attributes. `FileFilter` event now can filter only files (no directories and so on), so the `type` parameter will always be the same.

The alternative way to define the same filter is `AddFileFilter('size < 1024')`. The `AddFileFilter` function accepts only one expression for the `return` statement, but it's more efficient - all the expressions registered with this function are combined together to produce just one filter function and that makes the filtering faster.

The builtin option `--filter`/`-f` allows to filter files with Lua code:

    fa a arc "--filter= return size < 1e6"   "-f size>1000"


<a name="options"/>

## Handling program options

Part of options are defined in the C++ code and part in the builtin Lua code. You can define more options using Lua code in the config file. But irrespective of their origin, all options are placed in the single table with entries looking like that:
```lua
{
name: 'autogenerate', 
priority: 0,
prefixes: {'-ag[FORMAT]', '--autogenerate=[FORMAT]'}, 
description: 'append to archive name string generated by strftime',
parser: function(param) ... end,
post_handler: function() ... end
}
```

Table fields has the following meaning:
* `name` is the unique string indentifying the option. Table can't contain several options with the same name, instead attempt to define option with the same name will replace existing definition with the new one. This way you can modify or completely replace builtin options defined by the Lua and C++ code.
* `priority` defines [the order of option parsing](#options-order)
* `prefixes` are 1) displayed in the program help, and 2) used for [option parsing](#options-parsing-algorithm)
* `description` is only displayed in the program help 
* `parser` is called to recognize the option data
* `post_handler` is called after processing all options in the command line and expected to perform actual work requested by the option

If you know the option name, you can:
* modify the textual part of option definition by calling `AddOption(name, [priority,] prefixes, description)`. `Priority` may be omitted and defaults to 0.
* remove the option by calling `RemoveOption(name)`

Here you can find [[names of C++ options|0.11/Builtin-CPP-option-definitions.md]] and [[names of builtin Lua options|0.11/Builtin-Lua-option-definitions.md]].


<a name="options-high-level"/>

### High-level way of option definition

There are 3 ways to define new option: high-level, mid-level and low-level. Lower levels are more flexible, but less organized. It's recommended to define options at the highest level possible. High-level way to define/modify option is implemented by the function call:

    AddOption(name, [priority,] prefixes, description, type, post_handler)

Example: 

```lua
AddOption('min_size', 
          '-smBYTES --min-size=BYTES --SizeMore=BYTES', 
          'minimum filesize to process',
          OPTION_BYTES,  
          function(min_size) AddFileFilter('size>='..min_size) end)
```

Option `type` should be one of the following constants:
* OPTION_BOOL - assigns `true` value to the option, parsing fails if any extra chars are passed after the option prefix
* OPTION_STRING/OPTION_LIST - accepts any string
* OPTION_NUMBER - parses parameter as floating-point number, i.e. `1.5e6` is valid value
* OPTION_POWER, OPTION_BYTES, OPTION_KILOBYTES, OPTION_MEGABYTES, OPTION_GIGABYTES and so on - parameter is parsed as size in bytes. It allows any floating-point number, optionally followed by any of ^, b, k, kb, m, mb... The suffix defines interpretation of the numeric part (`N^` means `pow(2,N)`). When suffix is omitted, it's determined from the option `type`

`Type` defines the values that option may have. Parsed option value assigned to `optvalue[name]`. If option type is OPTION_LIST, this variable will contain list of all option values, otherwise it will contain the single boolean/string/number representing the last option value. If option wasn't encountered in the command, `optvalue[name]` will remain `nil`.

Post-processing handler is the function called after processing all input options, and only if this specific option was encountered in the command. The option value `optvalue[name]` is passed to the handler. If post-processing failed, the handler should return string describing the error.


<a name="options-mid-level"/>

### Mid-level way of option definition

Mid-level way to define/modify option is implemented by the function call:

    AddOption(name, [priority,] prefixes, description, parser, post_handler)

The following definition is equivalent to the high-level one in the previous section: 

```lua
AddOption('min_size', 
          '-smBYTES --min-size=BYTES --SizeMore=BYTES', 
          'minimum filesize to process',

          function(param)
              local size = parse_mem(param,'b')
              if size then
                  optvalue.min_size = size
              else
                  return 'cannot parse "'..param..'" as size'
              end
          end,

          function() 
              if optvalue.min_size then
                  AddFileFilter('size>=' .. optvalue.min_size) 
              end
          end)
```

Differences:
* High-level method automatically generates the parser function that checks option value correctness according to the `type`, then either assigns parsed value to `optvalue[name]` or returns error message. On mid-level, you should implement it yourself and it's recommended to save option value to the same `optvalue[name]` variable. OTOH, you get full control of the option parsing, and mid-level approach is recommended for options that require more specific value checks or custom error messages.
* Post-processing handler is called anyway and doesn't have a parameter. It's your duty to extract option value from the global variable where you have stored it, and check that this value isn't empty.

So, high-level method is just a thin wrapper around mid-level one, adding above-mentioned features.


<a name="options-low-level"/>

## Low-level way: handling Option and PostOption events

The low-level way to define options is to handle `Option` and `PostOption` events directly. Going this way, you need first to add bare option description to the table:

```lua
AddOption('min_size', 
          '-smBYTES --min-size=BYTES --SizeMore=BYTES', 
          'minimum filesize to process')
```

It lacks event handlers and therefore will be used only for the help screen. Then we are going to register `Option` and `PostOption` event handlers:

```lua
onOption (function (option)
    local param = option:start_with('-sm','--min-size=','--SizeMore=')
    if param then
        local size = parse_mem(param,'b')
        if size then
            optvalue.min_size = size
            return 1
        end
    end
end)

onPostOption(function()
    if optvalue.min_size then
        AddFileFilter('size>=' .. optvalue.min_size) 
    end
end)
```

`Option` handler will be called for each option in the command, so it's your duty to filter out options by the prefix. For this task, the `start_with` function/method is provided that returns remainder of the string if it has on of given prefixes, and `nil` otherwise. The handler should return `1` if option is successfully consumed, and `nil` otherwise. There is no way to return error message.

`PostOption` event handlers are called at the same time and has the same parameters (none) as post-processing handlers associated to the options.

The main drawback of low-level option handling is that option description, parser and post-processing handler are no more assocaited with each other. The `RemoveOption` call will remove only the option description, but cannot deactivate the event handlers. The `Option` handler will be called at unspecified moment and should manually ensure correct parsing of overloaded options instead of relying on the [parsing order](#options-order). And it cannot return an error message. That's why I don't recommend to use this way, especially in publicly-shared code.


<a name="options-order"/>

## Parsing order

Some options are overloaded, providing more than one parsing for the same option string. This overloading is resolved by checking all option parsers in the predefined order - the first parser that succeeds "steals" the option. If no parser accepted the option, the program displays error messages from them all:

```
C:\>fa a arc -sla

  ERROR! Failed parsing of "-sla" in the command line:
    as '-slBYTES' option: cannot parse "a" as size
    as '-sGROUPING' option: cannot parse "la" as file grouping specification
```

Options are sorted by the priority (higher priorities first) and then by the length of short prefix, i.e. prefix started with single '-' (longer prefixes first). Sorting by short prefixes ensures that most specific prefixes will be tried first (long prefixes i.e. those started with '--' are usually don't overlap, in particular because they usually include '=' at the end). And a few cases when the "short prefix rule" doesn't work, you can solve with priorities. It's recommended to assign priorities that are multiply of 100 in order to keep space for insertion in-between.

The following example demonstrates options sorted according to this rule (only priority and prefixes fields are shown):
```lua
{ 100, '-ab[SIZE]'}
{   0, '-abc[SIZE]  --x=SIZE'}
{   0, '-ab[SIZE]   --xy=SIZE'}
{   0, '-a[SIZE]    --xyz=SIZE'}
{   0, '            --xyzt=SIZE'}
{-100, '-ab[SIZE]'}
```


<a name="options-parsing-algorithm"/>

### Parsing algorithm

Option parser works by the following algorithm:

1. it stripes description part from option prefixes, for example `-ag[FORMAT] --autogenerate=[FORMAT]` list is transformed into `{'-ag', '--autogenerate='}` (description is considered as capital letters and brackets at the end of line)
2. it sorts option list as [described above](#options-order)
3. it checks each option in this order against the current option from command; the check is performed using `cmdline_option:start_with(option.striped_prefixes)` and if `start_with` returns non-nil value, the `option.parser` is executed on its result
4. the first parser that succeeds consumes the option, if all parsers failed then collection of error messages they have returned is printed
