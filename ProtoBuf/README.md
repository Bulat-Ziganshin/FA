A minimal C++ ProtoBuf library that is
- easy to learn
- easy to use
- adds minimal overhead to your executable

Also:
- easy to grok and hack, the entire library is only 400 LOC
- fast enough, but not super-optimized for speed
- generator of corresponding C++ structures and encoders/decoders from .pbs (compiled .proto) files
- the closest competitor is [protozero](https://github.com/mapbox/protozero)

This library is sincerely yours if you need to quickly implement encoding/decoding of
simple ProtoBuf messages without inflating your program.
There is no any build infrastructure - if you need this code, just grab it and go!

Files:
- [ProtoBufEncoder.cpp](ProtoBufEncoder.cpp) - the encoding library
- [ProtoBufDecoder.cpp](ProtoBufDecoder.cpp) - the decoding library
- [generator.cpp](src/generator/generator.cpp) - generator of encoders/decoders from .pbs files
- [decoder.cpp](decoder.cpp) - schema-less decoder of arbitrary ProtoBuf messages
- Example:
    - [main.cpp](main.cpp) - brief usage example
    - [Example.proto](Example.proto) - ProtoBuf definition of the serialized structure
    - [Example.pb.cpp](Example.pb.cpp) - auto-generated corresponding C++ structure and ProtoBuf encoder/decoder for it

Features currently implemented and planned:
- [x] encoding & decoding (requires C++17, may be lowered to C++11 by replacing uses of std::string_view with std::string)
- [x] any scalar/message fields, including repeated and packed ones
- [x] string/bytes fields can be stored in any type convertible from std::string_view
- [x] repeated fields can be stored in any container implementing push_back() and begin()/end()
- [x] the generated code checks presence of required fields in the decoded message
- [ ] support of enum/oneof/map fields and nested message type definitions by the code generator
(and thus dogfooding it)
- [ ] validation of enum, integer and bool values by the generated code
- [ ] big-endian architectures
- [ ] [efficient upb read_varint](https://github.com/protocolbuffers/protobuf/blob/a2f92689dac8a7dbea584919c7de52d6a28d66d1/upb/wire/decode.c#L122)
- [ ] group wire format



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

But on top of that, Codegen generates all the code necessary
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



## Going deeper

But even if you want to write (de)serializers manually, it's also easy:

```cpp
void MainMessage::ProtoBufEncode(ProtoBufEncoder &pb)
{
    pb.put_string(1, name);
    pb.put_double(2, weight);
    pb.put_repeated_int32(3, ids);
}

void MainMessage::ProtoBufDecode(std::string_view buffer)
{
    ProtoBufDecoder pb(buffer);

    while(pb.get_next_field())
    {
        switch(pb.field_num)
        {
            case 1: pb.get_string(&name); break;
            case 2: pb.get_double(&weight); break;
            case 3: pb.get_repeated_int32(&ids); break;
            default: pb.skip_field();
        }
    }
}
```

I.e. you just use put_<FIELD_TYPE> or put_repeated_<FIELD_TYPE> to write a [repeated] field,
and get_<FIELD_TYPE> or get_repeated_<FIELD_TYPE> to read one.
Field number should be the first parameter in put_* calls,
and placed in the case label before get_* calls.



## Boring details

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
