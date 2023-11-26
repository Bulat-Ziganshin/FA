// This file should be auto-generated from Example.proto

struct Filter
{
    int64_t size = 42;
    std::string name = "DEFAULT NAME";
    std::vector<int64_t> values;
    std::vector<std::string> subnames;

    bool has_size = false;
    bool has_name = false;

    void ProtoBufDecode(ProtoBufDecoder &pb);
}


void Filter::ProtoBufDecode(ProtoBufDecoder &pb)
{
    int field_num, field_type;

    while( pb.get_next_field( &field_num, &field_type))
    {
        switch(field_num)
        {
            case 1: pb.parse_integer_field( field_type, &size, &has_size); break;
            case 2: pb.parse_string_field ( field_type, &name, &has_name); break;
            case 3: pb.parse_repeated_integer_field( field_type, &values); break;
            case 4: pb.parse_repeated_string_field ( field_type, &subnames); break;
            default: pb.skip_field( field_type);
        }
    }
}
