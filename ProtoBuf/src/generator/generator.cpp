const char* USAGE =
"Generator of C++ decoder from compiled ProtoBuf schema\n"
"  Usage: generator file.pbs\n";

#include <string>
#include <cctype>
#include <iostream>
#include <fstream>
#include <iterator>
#include <format>

#include "ProtoBufDecoder.cpp"
#include "descriptor.pb.cpp"


constexpr const char* FILE_TEMPLATE = R"---(// This file was auto-generated from {}
#include <cstdint>
#include <string>
#include <vector>

)---";

constexpr const char* MESSAGE_TEMPLATE = R"---(
struct {0}
{{
{1}
{2}
    void ProtoBufDecode(ProtoBufDecoder &pb);
}};


void {0}::ProtoBufDecode(ProtoBufDecoder &pb)
{{
    int field_num, wire_type;

    while( pb.get_next_field( &field_num, &wire_type))
    {{
        switch(field_num)
        {{
{3}
            default: pb.skip_field(wire_type);
        }}
    }}
}}
)---";



std::string_view domain_string(FieldDescriptorProto &field)
{
    switch(field.type)
    {
        case FieldDescriptorProto::TYPE_DOUBLE:
        case FieldDescriptorProto::TYPE_FLOAT:
            return "fp";

        case FieldDescriptorProto::TYPE_SINT32:
        case FieldDescriptorProto::TYPE_SINT64:
            return "zigzag";

        case FieldDescriptorProto::TYPE_STRING:
        case FieldDescriptorProto::TYPE_BYTES:
            return "bytearray";

        case FieldDescriptorProto::TYPE_MESSAGE:
            return "message";

        case FieldDescriptorProto::TYPE_GROUP:
            return "?group";

        default:
            return "integral";
    }
}

std::string_view scalar_type_string(FieldDescriptorProto &field)
{
    switch(field.type)
    {
        case FieldDescriptorProto::TYPE_DOUBLE:   return "double";
        case FieldDescriptorProto::TYPE_FLOAT:    return "float";
        case FieldDescriptorProto::TYPE_INT64:    return "int64_t";
        case FieldDescriptorProto::TYPE_UINT64:   return "uint64_t";
        case FieldDescriptorProto::TYPE_INT32:    return "int32_t";
        case FieldDescriptorProto::TYPE_FIXED64:  return "uint64_t";
        case FieldDescriptorProto::TYPE_FIXED32:  return "uint32_t";
        case FieldDescriptorProto::TYPE_BOOL:     return "bool";
        case FieldDescriptorProto::TYPE_STRING:   return "std::string_view";
        case FieldDescriptorProto::TYPE_GROUP:    return "?group";
        case FieldDescriptorProto::TYPE_MESSAGE:  return field.type_name.substr(1);
        case FieldDescriptorProto::TYPE_BYTES:    return "std::string_view";
        case FieldDescriptorProto::TYPE_UINT32:   return "uint32_t";
        case FieldDescriptorProto::TYPE_ENUM:     return "int32_t";
        case FieldDescriptorProto::TYPE_SFIXED32: return "int32_t";
        case FieldDescriptorProto::TYPE_SFIXED64: return "int64_t";
        case FieldDescriptorProto::TYPE_SINT32:   return "int32_t";
        case FieldDescriptorProto::TYPE_SINT64:   return "int64_t";
    }
    return "?type";
}

std::string type_string(FieldDescriptorProto &field)
{
    auto result = scalar_type_string(field);

    if (field.label == FieldDescriptorProto::LABEL_REPEATED) {
        return std::format("std::vector<{}>", result);
    } else {
        return std::string(result);
    }
}


void generator(FileDescriptorSet &proto)
{
    auto file = proto.file[0];

    for (auto message_type: file.message_type)
    {
        std::string fields_defs, has_fields_defs, decode_cases;

        for (auto field: message_type.field)
        {
            // Generate message structure
            std::string default_str;
            if (field.has_default_value) {
                bool is_bytearray_field = (field.type==FieldDescriptorProto::TYPE_STRING || field.type==FieldDescriptorProto::TYPE_BYTES);
                const char* quote_str = (is_bytearray_field? "\"" : "");
                default_str = std::format(" = {0}{1}{0}", quote_str, field.default_value);
            }

            auto type_str = type_string(field);
            fields_defs += std::format("    {} {}{};\n", type_str, field.name, default_str);

            if (field.label != FieldDescriptorProto::LABEL_REPEATED) {
                has_fields_defs += std::format("    bool has_{} = false;\n", field.name);
            }

            // Generate message decoding function
            auto domain = domain_string(field);
            std::string decoder;

            if (field.label == FieldDescriptorProto::LABEL_REPEATED) {
                decoder = std::format("pb.parse_repeated_{}_field( wire_type, &{})", domain, field.name);
            } else {
                decoder = std::format("pb.parse_{0}_field( wire_type, &{1}, &has_{1})", domain, field.name);
            }

            decode_cases += std::format("            case {}: {}; break;\n", field.number, decoder);
        }

        std::cout << std::format(MESSAGE_TEMPLATE, message_type.name, fields_defs, has_fields_defs, decode_cases);
    }
}


int main(int argc, char** argv)
{
    if (argc != 2) {
        printf(USAGE);
        return 1;
    }

    auto filename = argv[1];
    std::ifstream ifs(filename, std::ios::binary);
    std::string str(std::istreambuf_iterator<char>{ifs}, {});

    try {
        ProtoBufDecoder pb(str);
        FileDescriptorSet proto;
        proto.ProtoBufDecode(pb);

        std::cout << std::format(FILE_TEMPLATE, filename);
        generator(proto);
    } catch (const std::exception& e) {
        fprintf(stderr, "Internal error: %s\n", e.what());
    }

    return 0;
}
