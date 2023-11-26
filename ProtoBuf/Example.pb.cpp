// This file should be auto-generated from Example.proto

struct Filter
{
    int64_t size = 42;
    char* name = "DEFAULT NAME";
    int64_t* values = nullptr;
    char** subnames = nullptr;

    size_t num_values = 0;
    size_t num_subnames = 0;

    bool has_size = false;
    bool has_name = false;

    void ProtoBufEncode(ProtoBufEncoder &pb);
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
            case 3: pb.parse_repeated_integer_field( field_type, &values, &num_values); break;
            case 4: pb.parse_repeated_string_field ( field_type, &subnames, &num_subnames); break;
            default: pb.skip_field( field_type);
        }
    }
}
