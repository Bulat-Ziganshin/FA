// This file will be auto-generated from descriptor.proto when I grow up
#include <cstdint>
#include <string>
#include <vector>

// Field
struct FieldDescriptorProto
{
    enum {
        TYPE_DOUBLE = 1,
        TYPE_FLOAT = 2,
        TYPE_INT64 = 3,
        TYPE_UINT64 = 4,
        TYPE_INT32 = 5,
        TYPE_FIXED64 = 6,
        TYPE_FIXED32 = 7,
        TYPE_BOOL = 8,
        TYPE_STRING = 9,
        TYPE_GROUP = 10,
        TYPE_MESSAGE = 11,
        TYPE_BYTES = 12,
        TYPE_UINT32 = 13,
        TYPE_ENUM = 14,
        TYPE_SFIXED32 = 15,
        TYPE_SFIXED64 = 16,
        TYPE_SINT32 = 17,
        TYPE_SINT64 = 18,
    };

    enum {
      LABEL_OPTIONAL = 1,
      LABEL_REPEATED = 3,
      LABEL_REQUIRED = 2,
    };

    std::string_view name;
    int32_t number;
    int32_t label;
    int32_t type;
    std::string_view type_name;
    std::string_view default_value;

    bool has_name = false;
    bool has_number = false;
    bool has_label = false;
    bool has_type = false;
    bool has_type_name = false;
    bool has_default_value = false;

    void ProtoBufDecode(ProtoBufDecoder &pb);
};


// Message
struct DescriptorProto
{
    std::string_view name;
    std::vector<FieldDescriptorProto> field;

    bool has_name = false;

    void ProtoBufDecode(ProtoBufDecoder &pb);
};


// Single .proto file
struct FileDescriptorProto
{
    std::string_view name;
    std::vector<DescriptorProto> message_type;

    bool has_name = false;

    void ProtoBufDecode(ProtoBufDecoder &pb);
};


// Multiple .proto files
struct FileDescriptorSet
{
    std::vector<FileDescriptorProto> file;

    void ProtoBufDecode(ProtoBufDecoder &pb);
};


void FieldDescriptorProto::ProtoBufDecode(ProtoBufDecoder &pb)
{
    int field_num, field_type;

    while( pb.get_next_field( &field_num, &field_type))
    {
        switch(field_num)
        {
            case 1: pb.parse_bytearray_field(field_type, &name,          &has_name); break;
            case 3: pb.parse_integral_field (field_type, &number,        &has_number); break;
            case 4: pb.parse_integral_field (field_type, &label,         &has_label); break;
            case 5: pb.parse_integral_field (field_type, &type,          &has_type); break;
            case 6: pb.parse_bytearray_field(field_type, &type_name,     &has_type_name); break;
            case 7: pb.parse_bytearray_field(field_type, &default_value, &has_default_value); break;
            default: pb.skip_field( field_type);
        }
    }

    if(! has_name) {
        throw std::runtime_error("Decoded protobuf has no required field FieldDescriptorProto.name");
    }
}


void DescriptorProto::ProtoBufDecode(ProtoBufDecoder &pb)
{
    int field_num, field_type;

    while( pb.get_next_field( &field_num, &field_type))
    {
        switch(field_num)
        {
            case 1: pb.parse_bytearray_field( field_type, &name, &has_name); break;
            case 2: pb.parse_repeated_message_field( field_type, &field); break;
            default: pb.skip_field( field_type);
        }
    }

    if(! has_name) {
        throw std::runtime_error("Decoded protobuf has no required field DescriptorProto.name");
    }
}


void FileDescriptorProto::ProtoBufDecode(ProtoBufDecoder &pb)
{
    int field_num, field_type;

    while( pb.get_next_field( &field_num, &field_type))
    {
        switch(field_num)
        {
            case 1: pb.parse_bytearray_field( field_type, &name, &has_name); break;
            case 4: pb.parse_repeated_message_field( field_type, &message_type); break;
            default: pb.skip_field( field_type);
        }
    }

    if(! has_name) {
        throw std::runtime_error("Decoded protobuf has no required field FileDescriptorProto.name");
    }
}


void FileDescriptorSet::ProtoBufDecode(ProtoBufDecoder &pb)
{
    int field_num, field_type;

    while( pb.get_next_field( &field_num, &field_type))
    {
        switch(field_num)
        {
            case 1: pb.parse_repeated_message_field( field_type, &file); break;
            default: pb.skip_field( field_type);
        }
    }
}
