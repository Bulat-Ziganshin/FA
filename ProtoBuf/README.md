This is minimum memorum implementation of ProtoBuf,
written specifically for FA'Next and thus supporting only features it may need.
It's optimized for code size, and current (unfinished) code is only 150 lines long.
The closest (and working!) competition is [protozero](https://github.com/mapbox/protozero).

Minimal decoder of ProtoBuf messages with planned code generator:
- [Example.proto](Example.proto) - definition of the serialized structure
- [Example.pb.cpp](Example.pb.cpp) - auto-generated C++ structure and ProtoBuf decoder for it
- [ProtoBufDecoder.cpp](ProtoBufDecoder.cpp) - library used by the decoder
- [main.cpp](main.cpp) - brief usage example

Currently supported:
- C++ decoder
- integral, string and repeated string fields

Support planned for:
- C++ encoder
- code generator from .proto files
- std::string_view as (repeated) fields
- float/double fields
- sub-messages
- big-endian architectures
- [efficient upb read_varint](https://github.com/protocolbuffers/protobuf/blob/a2f92689dac8a7dbea584919c7de52d6a28d66d1/upb/wire/decode.c#L122)

Not planned:
- other languages (may be except for Lua)
- packed repeated fields
- any validation (UTF-8, enums, integers)
