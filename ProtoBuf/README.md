A minimal C++ ProtoBuf library that is
- easy to learn
- easy to use
- adds minimal overhead to your executable


## Motivating example

Let's say that you wrote this message definition:
```proto
message Person
{
    required string name    = 1 [default = "AnnA"];
    optional double weight  = 2 [default = 3.14];
    repeated int32  numbers = 3;
}
```

Codegen translates this definition to plain C++ structure:
```cpp
struct Person
{
    std::string name = "AnnA";
    double weight = 3.14;
    std::vector<int32_t> numbers;
...
};
```

But on top of this, Codegen generates all the code necessary
to serialize Person to the ProtoBuf format and
deserialize Person from the ProtoBuf format:
```cpp
// Encode Person into a string buffer
std::string protobuf_msg = ProtoBufEncode(person);

// Decode Person from a string buffer
Person person2 = ProtoBufDecode<Person>(protobuf_msg);
```

And that's all you need to know to start using the library.
Check technical details in Tutorial.


## Details

This is a minimal implementation of C++ ProtoBuf library:
- optimized for code size, the entire library is only 400 LOC
- reasonable speed due to use of std::string_view
- generator of corresponding C++ structures and encoders/decoders from .pbs (compiled .proto) files
- the closest competition is [protozero](https://github.com/mapbox/protozero)

This library is sincerely yours if you need to quickly implement encoding/decoding of
simple ProtoBuf messages without inflating your program.
There is no any build infrastructure - if you need this code, just grab it and go!

Files:
- [Example.proto](Example.proto) - ProtoBuf definition of the serialized structure
- [Example.pb.cpp](Example.pb.cpp) - auto-generated corresponding C++ structure and ProtoBuf encoder/decoder for it
- [ProtoBufEncoder.cpp](ProtoBufEncoder.cpp) - library used by the encoder
- [ProtoBufDecoder.cpp](ProtoBufDecoder.cpp) - library used by the decoder
- [main.cpp](main.cpp) - brief usage example
- [decoder.cpp](decoder.cpp) - schema-less decoder of arbitrary ProtoBuf messages
- [generator.cpp](src/generator/generator.cpp) - generator of encoders/decoders from .pbs files

Features currently implemented and planned:
- [x] encoding & decoding (requires C++17, may be lowered to C++11 by replacing uses of std::string_view with std::string)
- [x] any scalar/message fields, including repeated ones
- [x] string/bytes fields can be stored in any type convertible from std::string_view
- [x] repeated fields can be stored in any container implementing push_back() and begin()/end()
- [x] the generated code checks presence of required fields in the decoded message
- [ ] packed repeated fields
- [ ] support of enum/oneof/map fields and nested message type definitions by the code generator
- [ ] validation of enum, integer and bool values by the generated code
- [ ] big-endian architectures
- [ ] [efficient upb read_varint](https://github.com/protocolbuffers/protobuf/blob/a2f92689dac8a7dbea584919c7de52d6a28d66d1/upb/wire/decode.c#L122)
- [ ] group wire format

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
