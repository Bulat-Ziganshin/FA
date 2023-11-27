// This file will be auto-generated from Example.proto when I grow up
#include <cstdint>
#include <string>
#include <vector>


struct Filter
{
    int64_t size = 42;
    std::string_view name = "DEFAULT NAME";
    std::vector<int64_t> values;
    std::vector<std::string_view> subnames;

    bool has_size = false;
    bool has_name = false;

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
            default: pb.skip_field( field_type);
        }
    }
}
