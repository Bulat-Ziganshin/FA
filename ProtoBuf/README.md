This is a minimal implementation of C++ ProtoBuf decoding library:
- optimized for code size, the entire decoding library is only 200 LOC
- reasonable speed due to use of std::string_view
- generator of corresponding C++ structures and decoders from .pbs (compiled .proto) files
- the closest competition is [protozero](https://github.com/mapbox/protozero)

This library is sincerely yours if you need to quickly implement decoding of
simple ProtoBuf messages without inflating your program.
There is no any build infrastructure - if you need this code, just grab it and go!

Files:
- [Example.proto](Example.proto) - ProtoBuf definition of the serialized structure
- [Example.pb.cpp](Example.pb.cpp) - auto-generated corresponding C++ structure and ProtoBuf decoder for it
- [ProtoBufDecoder.cpp](ProtoBufDecoder.cpp) - library used by the decoder
- [main.cpp](main.cpp) - brief usage example
- [decoder.cpp](decoder.cpp) - schema-less decoder of arbitrary ProtoBuf messages
- [generator.cpp](src/generator/generator.cpp) - generator of decoders from .pbs files

Currently supported:
- only decoding (requires C++17, may be lowered to C++11 by replacing uses of std::string_view with std::string)
- any scalar/message fields, including repeated ones
- string/bytes fields can be stored in any type convertible from std::string_view
- repeated fields can be stored in any container implementing push_back()
- the generated code checks presence of required fields in the decoded message

Support planned for:
- encoding, including automatic generation of encoders from .pbs files
- packed repeated fields
- group wire format
- big-endian architectures
- validation of enum, integer and bool values by the generated code
- support of enum/oneof fields and nested message type definitions by the code generator
- [efficient upb read_varint](https://github.com/protocolbuffers/protobuf/blob/a2f92689dac8a7dbea584919c7de52d6a28d66d1/upb/wire/decode.c#L122)

Compared to the official ProtoBuf library, it allows more flexibility
in modifying the field type without losing the decoding compatibility.
You can make any changes to field type as far as it stays inside the same "type domain":
- FP domain - only float and double
- zigzag domain - includes sint32 and sint64
- bytearray domain - strings, bytes and sub-messages
- integrals domain - all remaining scalar types (enum, bool, `int*`, `uint*`)
- aside of that, fixed-width integral fields are compatible with both integral and zigzag domain
- allows to switch between I32, I64 and VARINT representations for the same field as far as field type keept inside the same domain
- note that when changing the field type, values will be decoded correctly only if they fit into the range of both old and new field type - for integral types; while precision will be truncated to 32 bits - for FP types
