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
    void parse_zigzag_integer_field(int field_type, IntegerType *field, bool *has_field)
    {
        uint64_t value = parse_integer_value(field_type);

        *field = IntegerType(value/2);
        if(value & 1)  *field = IntegerType(-1) - *field;
        *has_field = true;
    }

    template <typename ByteArrayType>
    void parse_bytearray_field(int field_type, ByteArrayType *field, bool *has_field)
    {
        *field = parse_bytearray_value(field_type);
        *has_field = true;
    }

    template <typename RepeatedByteArrayType>
    void parse_repeated_bytearray_field(int field_type, RepeatedByteArrayType *field)
    {
        field->push_back( parse_bytearray_value(field_type));
    }


    std::string_view parse_bytearray_value(int field_type)
    {
        if(field_type != FT_LEN)  {throw ...;}

        uint64_t len = read_varint();
        advance_ptr(len);

        return std::string_view(ptr-len, len);
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

    template <typename FixedType>
    static FixedType ReadLE(void* ptr)
    {
        // TODO: reverse byte order on big-endians
        FixedType value;
        memcpy(&value, ptr, sizeof(value));
        return value;
    }
}
