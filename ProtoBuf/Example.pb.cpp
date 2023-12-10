// This file was auto-generated from Example.pbs
#include <cstdint>
#include <string>
#include <vector>


struct SubMessage
{
    int64_t req_int64;
    int32_t opt_sint32;
    uint64_t req_uint64;
    uint32_t opt_fixed32;
    float req_float;
    std::string_view opt_string = "DEFAULT STRING";
    std::vector<int32_t> rep_int32;
    std::vector<uint64_t> rep_uint64;
    std::vector<double> rep_double;

    bool has_req_int64 = false;
    bool has_opt_sint32 = false;
    bool has_req_uint64 = false;
    bool has_opt_fixed32 = false;
    bool has_req_float = false;
    bool has_opt_string = false;

    void ProtoBufEncode(ProtoBufEncoder &pb);
    void ProtoBufDecode(ProtoBufDecoder &pb);
};


void SubMessage::ProtoBufEncode(ProtoBufEncoder &pb)
{
    pb.write_varint_field(1, req_int64);
    pb.write_zigzag_field(2, opt_sint32);
    pb.write_varint_field(3, req_uint64);
    pb.write_fixed_width_field(4, opt_fixed32);
    pb.write_fixed_width_field(5, req_float);
    pb.write_bytearray_field(6, opt_string);
    pb.write_repeated_varint_field(11, rep_int32);
    pb.write_repeated_varint_field(12, rep_uint64);
    pb.write_repeated_fixed_width_field(13, rep_double);

}

void SubMessage::ProtoBufDecode(ProtoBufDecoder &pb)
{
    while(pb.get_next_field())
    {
        switch(pb.field_num)
        {
            case 1: pb.parse_integral_field(&req_int64, &has_req_int64); break;
            case 2: pb.parse_zigzag_field(&opt_sint32, &has_opt_sint32); break;
            case 3: pb.parse_integral_field(&req_uint64, &has_req_uint64); break;
            case 4: pb.parse_integral_field(&opt_fixed32, &has_opt_fixed32); break;
            case 5: pb.parse_fp_field(&req_float, &has_req_float); break;
            case 6: pb.parse_bytearray_field(&opt_string, &has_opt_string); break;
            case 11: pb.parse_repeated_integral_field(&rep_int32); break;
            case 12: pb.parse_repeated_integral_field(&rep_uint64); break;
            case 13: pb.parse_repeated_fp_field(&rep_double); break;

            default: pb.skip_field();
        }
    }

    if(! has_req_int64) {
        throw std::runtime_error("Decoded protobuf has no required field SubMessage.req_int64");
    }

    if(! has_req_uint64) {
        throw std::runtime_error("Decoded protobuf has no required field SubMessage.req_uint64");
    }

    if(! has_req_float) {
        throw std::runtime_error("Decoded protobuf has no required field SubMessage.req_float");
    }

}

struct MainMessage
{
    uint32_t opt_uint32;
    int64_t req_sfixed64;
    double opt_double = 3.14;
    std::string_view req_bytes;
    SubMessage req_msg;
    std::vector<int32_t> rep_sint32;
    std::vector<uint64_t> rep_fixed64;
    std::vector<std::string_view> rep_string;
    std::vector<SubMessage> rep_msg;

    bool has_opt_uint32 = false;
    bool has_req_sfixed64 = false;
    bool has_opt_double = false;
    bool has_req_bytes = false;
    bool has_req_msg = false;

    void ProtoBufEncode(ProtoBufEncoder &pb);
    void ProtoBufDecode(ProtoBufDecoder &pb);
};


void MainMessage::ProtoBufEncode(ProtoBufEncoder &pb)
{
    pb.write_varint_field(1, opt_uint32);
    pb.write_fixed_width_field(2, req_sfixed64);
    pb.write_fixed_width_field(3, opt_double);
    pb.write_bytearray_field(4, req_bytes);
    pb.write_message_field(5, req_msg);
    pb.write_repeated_zigzag_field(11, rep_sint32);
    pb.write_repeated_fixed_width_field(12, rep_fixed64);
    pb.write_repeated_bytearray_field(13, rep_string);
    pb.write_repeated_message_field(14, rep_msg);

}

void MainMessage::ProtoBufDecode(ProtoBufDecoder &pb)
{
    while(pb.get_next_field())
    {
        switch(pb.field_num)
        {
            case 1: pb.parse_integral_field(&opt_uint32, &has_opt_uint32); break;
            case 2: pb.parse_integral_field(&req_sfixed64, &has_req_sfixed64); break;
            case 3: pb.parse_fp_field(&opt_double, &has_opt_double); break;
            case 4: pb.parse_bytearray_field(&req_bytes, &has_req_bytes); break;
            case 5: pb.parse_message_field(&req_msg, &has_req_msg); break;
            case 11: pb.parse_repeated_zigzag_field(&rep_sint32); break;
            case 12: pb.parse_repeated_integral_field(&rep_fixed64); break;
            case 13: pb.parse_repeated_bytearray_field(&rep_string); break;
            case 14: pb.parse_repeated_message_field(&rep_msg); break;

            default: pb.skip_field();
        }
    }

    if(! has_req_sfixed64) {
        throw std::runtime_error("Decoded protobuf has no required field MainMessage.req_sfixed64");
    }

    if(! has_req_bytes) {
        throw std::runtime_error("Decoded protobuf has no required field MainMessage.req_bytes");
    }

    if(! has_req_msg) {
        throw std::runtime_error("Decoded protobuf has no required field MainMessage.req_msg");
    }

}
