// This file was auto-generated from Example.pbs
#include <cstdint>
#include <string>
#include <vector>


struct SubMessage
{


    void ProtoBufEncode(ProtoBufEncoder &pb);
    void ProtoBufDecode(ProtoBufDecoder &pb);
};


void SubMessage::ProtoBufEncode(ProtoBufEncoder &pb)
{

}

void SubMessage::ProtoBufDecode(ProtoBufDecoder &pb)
{
    while(pb.get_next_field())
    {
        switch(pb.field_num)
        {

            default: pb.skip_field();
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

    void ProtoBufEncode(ProtoBufEncoder &pb);
    void ProtoBufDecode(ProtoBufDecoder &pb);
};


void Filter::ProtoBufEncode(ProtoBufEncoder &pb)
{
    pb.write_varint_field(1, size);
    pb.write_zigzag_field(2, altitude);
    pb.write_fixed_width_field(3, weight);
    pb.write_bytearray_field(4, name);
    pb.write_message_field(5, msg);
    pb.write_repeated_varint_field(11, more_uints);
    pb.write_repeated_zigzag_field(12, more_sints);
    pb.write_repeated_fixed_width_field(13, more_floats);
    pb.write_repeated_bytearray_field(14, more_strings);
    pb.write_repeated_message_field(15, more_msgs);

}

void Filter::ProtoBufDecode(ProtoBufDecoder &pb)
{
    while(pb.get_next_field())
    {
        switch(pb.field_num)
        {
            case 1: pb.parse_integral_field(&size, &has_size); break;
            case 2: pb.parse_zigzag_field(&altitude, &has_altitude); break;
            case 3: pb.parse_fp_field(&weight, &has_weight); break;
            case 4: pb.parse_bytearray_field(&name, &has_name); break;
            case 5: pb.parse_message_field(&msg, &has_msg); break;
            case 11: pb.parse_repeated_integral_field(&more_uints); break;
            case 12: pb.parse_repeated_zigzag_field(&more_sints); break;
            case 13: pb.parse_repeated_fp_field(&more_floats); break;
            case 14: pb.parse_repeated_bytearray_field(&more_strings); break;
            case 15: pb.parse_repeated_message_field(&more_msgs); break;

            default: pb.skip_field();
        }
    }

    if(! has_size) {
        throw std::runtime_error("Decoded protobuf has no required field Filter.size");
    }

}
