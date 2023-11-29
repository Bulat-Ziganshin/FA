// This file was auto-generated from Example.pbs
#include <cstdint>
#include <string>
#include <vector>


struct SubMessage
{


    void ProtoBufDecode(ProtoBufDecoder &pb);
};


void SubMessage::ProtoBufDecode(ProtoBufDecoder &pb)
{
    int field_num, wire_type;

    while( pb.get_next_field( &field_num, &wire_type))
    {
        switch(field_num)
        {

            default: pb.skip_field(wire_type);
        }
    }

}

struct Filter
{
    int64_t size;
    int32_t altitude;
    float weight;
    std::string_view name = "DEFAULT NAME";
    SubMessage msg;
    std::vector<uint32_t> more_uints;
    std::vector<int64_t> more_sints;
    std::vector<double> more_floats;
    std::vector<std::string_view> more_strings;
    std::vector<SubMessage> more_msgs;

    bool has_size = false;
    bool has_altitude = false;
    bool has_weight = false;
    bool has_name = false;
    bool has_msg = false;

    void ProtoBufDecode(ProtoBufDecoder &pb);
};


void Filter::ProtoBufDecode(ProtoBufDecoder &pb)
{
    int field_num, wire_type;

    while( pb.get_next_field( &field_num, &wire_type))
    {
        switch(field_num)
        {
            case 1: pb.parse_integral_field( wire_type, &size, &has_size); break;
            case 2: pb.parse_zigzag_field( wire_type, &altitude, &has_altitude); break;
            case 3: pb.parse_fp_field( wire_type, &weight, &has_weight); break;
            case 4: pb.parse_bytearray_field( wire_type, &name, &has_name); break;
            case 5: pb.parse_message_field( wire_type, &msg, &has_msg); break;
            case 11: pb.parse_repeated_integral_field( wire_type, &more_uints); break;
            case 12: pb.parse_repeated_zigzag_field( wire_type, &more_sints); break;
            case 13: pb.parse_repeated_fp_field( wire_type, &more_floats); break;
            case 14: pb.parse_repeated_bytearray_field( wire_type, &more_strings); break;
            case 15: pb.parse_repeated_message_field( wire_type, &more_msgs); break;

            default: pb.skip_field(wire_type);
        }
    }

    if(! has_size) {
        throw std::runtime_error("Decoded protobuf has no required field Filter.size");
    }

}
