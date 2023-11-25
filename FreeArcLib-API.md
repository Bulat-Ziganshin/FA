Goals:
* provide C API to FreeArc functionality, similar to 7z.dll
* provide C APIs for each stage of command processing
* make these APIs stable and accessible from any language by using ProtoBuf to serialize all parameters
* provide alternative low-level C APIs for all these functions with direct access to С structures
* may be, provide some extra functionality to 7z.dll:
  * add ProtoBuf interfaces to 7z.dll functions
  * combine FreeArc cmdline processing with 7z.dll archive processing, essentially allowing FreeArc to process any archive type

We can classify provided APIs by the level of micro-management:
* [Command](#Command) - highest-level, executes an entire archiver command
* [Operation](#Operation) - provides individual operations from which a command can be constructed

We also discuss:
* [Fast vs Stable API](#fast-vs-stable-api) - internal and external API provided by the library
* [ProtoBuf implementation](#protobuf-implementation) - sketch of ProtoBuf structure for the Command

The implementation plan:
* Move main() to Lua side
* Modify FreearcCommand() to use fields in the Command instead of global variables
* Implement PortableFreearcCommand() that uses ProtoBuf for all parameters, including callbacks
* Modify Lua main() code to work with internal Command and then call PortableFreearcCommand()
* Further split FreearcCommand() into operations and provide ProtoBuf APIs to them
* Provide ProtoBuf APIs to 7z.dll functions and combine Lua cmdline processing with 7z.dll archive processing


## Command

FreearcCommand():
* executes an entire archiver command, i.e. its only effect is the modification of disk files and/or some callback calls
* returns almost nothing, probably only error code - all other information is passed back via Callback
* thus has C ABI, even if unstable. Also, it looks pretty similar to 7z.dll API
  * stable API requires only unpacking Command and packing Callback parameters
* its execution creates, modifies and finally destroys a FileDB object (see [Operation](#Operation))

Call parameters:
* version = high<<16 + low
  * high=0, incremented at incompatible API changes
  * low = sizeof(Command), thus allowing to copy passed Command over initialized actual Command structure that may contain extra fields at the end
* Command* - all command parameters, established by the processing of cmdline with config files
  * i.e. {char* cmd = "a"; char* arcname = "a.arc"; char** filenames = {"."}; char** cmethods = {"lzma"}...}
* void* - passed to callback
* `int(*)(void*, int, message*)` - callback called for UI/log, warnings/errors, file/method filtering and so on
  * int - message type
  * message is a union of structures providing extra info depending on the message

Portable proxy to FreearcCommand(), generated from ProtoBuf description of Command via ProtoBuf reflection:
* declaration of C++ struct Command, including default values of fields
* PortableFreearcCommand() decoding wire format of Command and then calling FreearcCommand()
* Lua/Python/Ruby... code encoding Command{cmd,arcname...} object into the wire format and then calling PortableFreearcCommand()

All modifications required to the current code:
* move main() to the Lua side, so it parses options and then calls FreeArcCommand(Command,Callback)
* make all C++ APIs, provided to Lua, global, i.e. independent of the C++ Program object
  * well, inside Callback execution we may need some instance-specific info, calling back for it once again
* modify Lua code to work with internal `command` variable before passing it to FreeArcCommand()
* modify Callback API to make it language-agnostic (now, it depends on C++/Lua bridge facilities)
  * we have a few message types, each having a fixed set of parameters - this calls for a serialization library, again


## Operation

Managing a database:
* db = Create() - create an empty database.
* Clear(db) - reset the database to an empty state.
* Close(db) - free memory occupied by the database.

Adding files to an archive:
* Scan(db, scan_settings) - scan the disk according to the settings, adding found files to the database
* Sort(db, sort_criteria) - sort files in the database
* Add(db, compression_settings) - create an archive from the files in the database

Extracting files from an archive:
* ReadDir(db, readdir_settings) - read the archive directory, adding these files to the database
* Size(db) - return the number of files in the database
* List(db, range) - list files in the given range
* Extract(db, extraction_settings) - extract files listed in the database from the archive


# Fast vs Stable API
Two API sets:
* Fast API: the actual C++ implementation, employing multiple function parameters, C structs, and C++ exceptions. It isn't intended to be consumed directly, except for reaching maximum speed in some cases (custom filters, custom sort order, listing files).
* Stable API: a thin layer over the Fast API, marshaling most arguments/results/exceptions in ProtoBuf messages. It thus provides a stable, language-agnostic API that can be consumed by static or dynamic linking. It semi-automatically maps to the Fast API.

Notes:
* Fast API is almost the existing one, except for the need to break the monolithic program_options structure into ~5 smaller structures with parameters of each specific operation
* Stable API is mostly straightforward as far as we define those small structures via ProtoBuf
* but the existing ProtoBuf implementations seem over-bloated, do we need N+1 one?
* alternatives: Thrift, FlexBuffers/FlatBuffers
* the remaining FreeArc'Next code is already mostly written in Lua, but we will still need to translate C++ remnants
* the existing program driver should be modified to run Lua main and to allow loading FreeArcLib from DLL


### ProtoBuf implementation

```ProtoBuf
syntax = "proto3";

message Filter
{
    required int64 size = 1;   // default = 42
    optional string name = 2;  // default = "DEFAULT NAME"
    repeated int64 values = 3;
    repeated string subnames = 4;
}
```

may be translated into

```C
struct Filter
{
    int64_t size = 42;
    char* name = "DEFAULT NAME";
    int64_t* values = nullptr;
    char** subnames = nullptr;

    size_t num_values = 0;
    size_t num_subnames = 0;

    bool has_size = false;
    bool has_name = false;

    void ProtoBufEncode(ProtoBufEncoder &pb);
    void ProtoBufDecode(ProtoBufDecoder &pb);
}


void Filter::ProtoBufDecode(ProtoBufDecoder &pb)
{
    while(pb.get_next_field())
    {
        switch(pb.field_num)
        {
            case 1: pb.parse_int(&size, &has_size); break;
            case 2: pb.parse_string(&name, &has_name); break;
            case 3: pb.parse_repeated_int(&values, &num_values); break;
            case 4: pb.parse_repeated_string(&subnames, &num_subnames); break;
            default: pb.skip_field();
        }
    }
}
```

with application's usage as:

```C
ProtoBufDecoder pb(buf,size);
filter.ProtoBufDecode(pb);
if(pb.error)
    abort("Internal error: " + pb.error_message());
```
