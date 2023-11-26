struct ProtoBufDecoder
{
    bool get_next_field(int* field_num, int* field_type)
    {
        if(error || (ptr == buf_end))  return false;

        uint64_t number = read_varint();
        if(error)  return false;

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
            if(error)                 return;
            if(buf_end - ptr < len)   {set_error(...); return;}
            ptr += len;
        } else {
            set_error(...);
        }
    }


    template <typename IntegerType>
    void parse_integer_field(int field_type, IntegerType *field, bool *has_field)
    {
        uint64_t value = parse_integer_value(field_type);
        if(error) return;

        *field = IntegerType(value);
        *has_field = true;
    }

    template <typename IntegerType>
    void parse_integer_field_with_sign(int field_type, IntegerType *field, bool *has_field)
    {
        uint64_t value = parse_integer_value(field_type);
        if(error) return;

        *field = IntegerType(value/2);
        if(value & 1)  *field = IntegerType(-1) - *field;
        *has_field = true;
    }

    void parse_string_field(int field_type, char **field, bool *has_field)
    {
        char *s = parse_string_value(field_type);
        if(error) return;

        *field = s;
        *has_field = true;
    }

    void parse_repeated_string_field(int field_type, char ***field, size_t *num_values)
    {
        char *s = parse_string_value(field_type);
        if(error) return;

        char **new_array = realloc(*field, (*num_values + 2) * sizeof(char*));
        if(new_array == nullptr)  {set_error(...); return;}

        new_array[*num_values] = s;
        new_array[*num_values + 1] = nullptr;

        *field = new_array;
        *num_values += 1;
    }


    char* parse_string_value(int field_type)
    {
        if(field_type != FT_LEN)  {set_error(...); return nullptr;}
        uint64_t len = read_varint();
        if(error)                 return nullptr;
        if(buf_end - ptr < len)   {set_error(...); return nullptr;}

        char *s = malloc(len+1);  // TODO: custom memory allocation
        if(s == nullptr)  {set_error(...); return nullptr;}

        memcpy(s, ptr, len);
        s[len] = 0;

        ptr += len;
        return s;
    }

    uint64_t parse_integer_value(int field_type)
    {
        if (field_type == FT_VARINT) {
            return read_varint();
        }

        if (field_type == FT_FIXED64) {
            if(buf_end - ptr < 8)  {set_error(...); return 0;}
            ptr += 8;
            return *(uint64_t*)(ptr-8);  // TODO: reverse byte order on big-endians
        }

        // TODO: parse FT_FIXED32

        set_error(...);
        return 0;
    }

    uint64_t read_varint()
    {
        uint64_t value = 0;
        int shift = 0;

        do {
            if(ptr == buf_end)  {set_error(...); return 0;}
            if(shift >= 64)     {set_error(...); return 0;}

            auto has_more_bytes = (*ptr & 128);
            uint64_t byte = (*ptr & 127);

            value |= (byte << shift);
            ptr++;  shift += 7;
        } while(has_more_bytes);

        return value;
    }
}
