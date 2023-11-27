struct ProtoBufDecoder
{
    uint8_t* ptr = nullptr;
    uint8_t* buf_end = nullptr;

    explicit ProtoBufDecoder(const std::string_view& view) noexcept
        : ptr     {(uint8_t*) (view.data())},
          buf_end {(uint8_t*) (view.data() + view.size())}
    {
    }

    void advance_ptr(int bytes)
    {
        if(buf_end - ptr < bytes)  throw std::runtime_error("Unexpected end of buffer");
        ptr += bytes;
    }


    template <typename FixedType>
    FixedType read_fixed_width()
    {
        FixedType value;

        void* old_ptr = ptr;
        advance_ptr(sizeof(value));

        memcpy(&value, old_ptr, sizeof(value));
        return value;  // TODO: reverse byte order on big-endian computers
    }

    uint64_t read_varint()
    {
        uint64_t value = 0;
        int shift = 0;

        do {
            if(ptr == buf_end)  throw std::runtime_error("Unexpected end of buffer in varint");
            if(shift >= 64)     throw std::runtime_error("More than 10 bytes in varint");

            auto has_more_bytes = (*ptr & 128);
            uint64_t byte = (*ptr & 127);

            value |= (byte << shift);
            ptr++;  shift += 7;
        } while(has_more_bytes);

        return value;
    }


    double parse_fp_value(int field_type)
    {
        switch(field_type) {
            case FT_FIXED64: return read_fixed_width<double>();
            case FT_FIXED32: return read_fixed_width<float>();
        }

        throw std::runtime_error("Can't parse floating-point value with field type " + std::to_string(field_type));
    }

    uint64_t parse_integer_value(int field_type)
    {
        switch(field_type) {
            case FT_VARINT:  return read_varint();
            case FT_FIXED64: return read_fixed_width<uint64_t>();
            case FT_FIXED32: return read_fixed_width<uint32_t>();
        }

        throw std::runtime_error("Can't parse integral value with field type " + std::to_string(field_type));
    }

    int64_t parse_zigzag_integer_value(int field_type)
    {
        if(field_type != FT_VARINT) {
            throw std::runtime_error("Can't parse zigzag integer with field type " + std::to_string(field_type));
        }

        uint64_t value = read_varint();
        return int64_t((value>>1) | (value<<63));
    }

    std::string_view parse_bytearray_value(int field_type)
    {
        if(field_type != FT_LEN) {
            throw std::runtime_error("Can't parse bytearray with field type " + std::to_string(field_type));
        }

        uint64_t len = read_varint();
        advance_ptr(len);

        return {ptr-len, len};
    }


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
            throw std::runtime_error("Unsupported field type " + std::to_string(field_type));
        }
    }


    template <typename IntegralType>
    void parse_integral_field(int field_type, IntegralType *field, bool *has_field)
    {
        uint64_t value = parse_integer_value(field_type);

        *field = IntegralType(value);
        *has_field = true;
    }

    template <typename RepeatedIntegralType>
    void parse_repeated_integral_field(int field_type, RepeatedIntegralType *field)
    {
        field->push_back( parse_integer_value(field_type));
    }

    template <typename IntegralType>
    void parse_zigzag_integral_field(int field_type, IntegralType *field, bool *has_field)
    {
        int64_t value = parse_zigzag_integer_value(field_type);

        *field = IntegralType(value);
        *has_field = true;
    }

    template <typename RepeatedIntegralType>
    void parse_repeated_zigzag_integral_field(int field_type, RepeatedIntegralType *field)
    {
        field->push_back( parse_zigzag_integer_value(field_type));
    }

    template <typename FloatingPointType>
    void parse_fp_field(int field_type, FloatingPointType *field, bool *has_field)
    {
        double value = parse_fp_value(field_type);

        *field = FloatingPointType(value);
        *has_field = true;
    }

    template <typename RepeatedFloatingPointType>
    void parse_repeated_fp_field(int field_type, RepeatedFloatingPointType *field)
    {
        field->push_back( parse_fp_value(field_type));
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
}
