// This file will be auto-generated from Example.proto when I grow up
#include <cstdint>
#include <string>
#include <vector>


struct SubMessage
{
    void ProtoBufDecode(ProtoBufDecoder &pb)
    {
    }
};


struct Filter
{
    int64_t size = 42;
    std::string_view name = "DEFAULT NAME";
    std::vector<int64_t> values;
    std::vector<std::string_view> subnames;
    SubMessage msg;
    std::vector<SubMessage> more_msgs;

    bool has_size = false;
    bool has_name = false;
    bool has_msg = false;

    void ProtoBufDecode(ProtoBufDecoder &pb);
};


void Filter::ProtoBufDecode(ProtoBufDecoder &pb)
{
    int field_num, field_type;

    while( pb.get_next_field( &field_num, &field_type))
    {
        switch(field_num)
        {
            case 1: pb.parse_integral_field( field_type, &size, &has_size); break;
            case 2: pb.parse_bytearray_field( field_type, &name, &has_name); break;
            case 3: pb.parse_repeated_integral_field( field_type, &values); break;
            case 4: pb.parse_repeated_bytearray_field( field_type, &subnames); break;
            case 5: pb.parse_message_field( field_type, &msg, &has_msg); break;
            case 6: pb.parse_repeated_message_field( field_type, &more_msgs); break;
            default: pb.skip_field( field_type);
        }
    }
}
