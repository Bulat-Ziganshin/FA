struct ProtoBufDecoder
{
    bool get_next_field(int* field_num, int* field_type)
    {
        if(ptr == buf_end)  return false;

        uint64_t number = read_varint();
        *field_num = (number >> 3);
        *field_type = (number & 7);

        return true;
    }

    void skip_field(int field_type)
    {
        if (field_type == FT_VARINT) {
            read_varint();
        } else if (field_type == FT_FIXED32) {
            advance_ptr(4);
        } else if (field_type == FT_FIXED64) {
            advance_ptr(8);
        } else if (field_type == FT_LEN) {
            uint64_t len = read_varint();
            advance_ptr(len);
        } else {
            throw ...;
        }
    }


    template <typename IntegerType>
    void parse_integer_field(int field_type, IntegerType *field, bool *has_field)
    {
        uint64_t value = parse_integer_value(field_type);

        *field = IntegerType(value);
        *has_field = true;
    }

    template <typename IntegerType>
    void parse_integer_field_with_sign(int field_type, IntegerType *field, bool *has_field)
    {
        uint64_t value = parse_integer_value(field_type);

        *field = IntegerType(value/2);
        if(value & 1)  *field = IntegerType(-1) - *field;
        *has_field = true;
    }

    void parse_string_field(int field_type, char **field, bool *has_field)
    {
        char *s = parse_string_value(field_type);

        *field = s;
        *has_field = true;
    }

    void parse_repeated_string_field(int field_type, char ***field, size_t *num_values)
    {
        char *s = parse_string_value(field_type);

        char **new_array = realloc(*field, (*num_values + 2) * sizeof(char*));
        if(new_array == nullptr)  {throw ...;}

        new_array[*num_values] = s;
        new_array[*num_values + 1] = nullptr;

        *field = new_array;
        *num_values += 1;
    }


    char* parse_string_value(int field_type)
    {
        if(field_type != FT_LEN)  {throw ...;}

        uint64_t len = read_varint();
        advance_ptr(len);

        char *s = malloc(len+1);  // TODO: custom memory allocation
        if(s == nullptr)  {throw ...;}

        memcpy(s, ptr-len, len);
        s[len] = 0;
        return s;
    }

    uint64_t parse_integer_value(int field_type)
    {
        if (field_type == FT_VARINT) {
            return read_varint();
        }

        if (field_type == FT_FIXED64) {
            advance_ptr(8);
            return ReadLE<uint64_t>(ptr-8);
        }

        if (field_type == FT_FIXED32) {
            advance_ptr(4);
            return ReadLE<uint32_t>(ptr-4);
        }

        throw ...;
    }

    uint64_t read_varint()
    {
        uint64_t value = 0;
        int shift = 0;

        do {
            if(ptr == buf_end)  {throw ...;}
            if(shift >= 64)     {throw ...;}

            auto has_more_bytes = (*ptr & 128);
            uint64_t byte = (*ptr & 127);

            value |= (byte << shift);
            ptr++;  shift += 7;
        } while(has_more_bytes);

        return value;
    }
}
