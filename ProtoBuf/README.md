This is a minimal implementation of ProtoBuf decoder:
- optimized for code size, the entire decoding library is 200 LOC
- encoder and compiler for .proto files are planned for the indefinite future
- the closest competition is [protozero](https://github.com/mapbox/protozero)

Files:
- [Example.proto](Example.proto) - ProtoBuf definition of the serialized structure
- [Example.pb.cpp](Example.pb.cpp) - corresponding C++ structure and ProtoBuf decoder for it
- [ProtoBufDecoder.cpp](ProtoBufDecoder.cpp) - library used by the decoder
- [main.cpp](main.cpp) - brief usage example

Currently supported:
- only C++ decoder (requires C++17 due to use of std::string_view)
- any scalar fields, repeated fields and sub-messages
- string/bytes fields can be stored in any type convertible from std::string_view
- repeated fields can be stored in any container implementing push_back()
- allows to switch between I32, I64 and VARINT representations for the same field as far as field type keept inside int/zigzag/FP domain; fixed-width integral fields are compatible both with int and zigzag domain

Support planned for:
- C++ encoder
- code generator from .proto files (can be implemented as backend for [pbtools](https://github.com/eerimoq/pbtools))
- packed repeated fields
- group wire format
- big-endian architectures
- [efficient upb read_varint](https://github.com/protocolbuffers/protobuf/blob/a2f92689dac8a7dbea584919c7de52d6a28d66d1/upb/wire/decode.c#L122)

Not planned:
- other languages (may be except for Lua)
- any validation (UTF-8, enums, integers)

There is no any build infrastructure - if you need this code, just grab it and go!
