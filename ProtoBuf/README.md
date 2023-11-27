This is minimum memorum implementation of ProtoBuf decoder,
written specifically for FA'Next and thus supporting only features it may need.
It's optimized for code size, and current (unfinished) code is only 150 lines long.
The nearest (and working!) competition is [protozero](https://github.com/mapbox/protozero).

Minimal decoder of ProtoBuf messages with planned code generator:
- [Example.proto](Example.proto) - definition of the serialized structure
- [Example.pb.cpp](Example.pb.cpp) - auto-generated C++ structure and ProtoBuf decoder for it
- [ProtoBufDecoder.cpp](ProtoBufDecoder.cpp) - library used by the decoder
- [main.cpp](main.cpp) - brief usage example

Currently supported:
- C++ decoder
- integral, string/bytearray and repeated fields
- std::vector<char>, std::string and std::string_view as string/bytearray implementations
- any containers implementing push_back() for repeated fields
- requires C++17 due to use of std::string_view

Support planned for:
- C++ encoder
- code generator from .proto files (may be implemented as another backend for [pbtools](https://github.com/eerimoq/pbtools))
- float/double fields
- sub-messages
- packed repeated fields
- big-endian architectures
- [efficient upb read_varint](https://github.com/protocolbuffers/protobuf/blob/a2f92689dac8a7dbea584919c7de52d6a28d66d1/upb/wire/decode.c#L122)

Not planned:
- other languages (may be except for Lua)
- any validation (UTF-8, enums, integers)

There is no any build infrastructure - if you need this code, just grab it and go!
