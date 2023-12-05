/*
Decoder library consists of 3 levels:
- 1st level defines read_varint() and read_fixed_width(), allowing to grab basic values from input buffer
- 2nd level defines parse_*_value(), allowing to read a field knowing field's type and wiretype
- 3rd level defines parse_*_field() helpers, although they aren't strictly necessary
*/

#include <string>
#include <cstring>
#include <cstdint>
#include <stdexcept>


struct ProtoBufDecoder
{
    enum WireType
    {
      WIRETYPE_VARINT = 0,
      WIRETYPE_FIXED64 = 1,
      WIRETYPE_LENGTH_DELIMITED = 2,
      WIRETYPE_START_GROUP = 3,
      WIRETYPE_END_GROUP = 4,
      WIRETYPE_FIXED32 = 5,
    };

    const char* ptr = nullptr;
    const char* buf_end = nullptr;
    int field_num;
    WireType wire_type;


    explicit ProtoBufDecoder(const std::string_view& view) noexcept
        : ptr     {view.data()},
          buf_end {view.data() + view.size()}
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

        auto old_ptr = ptr;
        advance_ptr(sizeof(value));

        memcpy(&value, old_ptr, sizeof(value));
        return value;  // TODO: reverse byte order on big-endian cpus
    }

    uint64_t read_varint()
    {
        uint64_t value = 0;
        uint64_t byte;
        int shift = 0;

        do {
            if(ptr == buf_end)  throw std::runtime_error("Unexpected end of buffer in varint");
            if(shift >= 64)     throw std::runtime_error("More than 10 bytes in varint");

            byte = *(uint8_t*)ptr;
            value |= ((byte & 127) << shift);
            ptr++;  shift += 7;
        }
        while(byte & 128);

        return value;
    }


    template <typename FloatingPointType>
    FloatingPointType parse_fp_value()
    {
        switch(wire_type) {
            case WIRETYPE_FIXED64: return read_fixed_width<double>();
            case WIRETYPE_FIXED32: return read_fixed_width<float>();
        }

        throw std::runtime_error("Can't parse floating-point value with field type " + std::to_string(wire_type));
    }

    uint64_t parse_integer_value()
    {
        switch(wire_type) {
            case WIRETYPE_VARINT:   return read_varint();
            case WIRETYPE_FIXED64:  return read_fixed_width<uint64_t>();
            case WIRETYPE_FIXED32:  return read_fixed_width<uint32_t>();
        }

        throw std::runtime_error("Can't parse integral value with field type " + std::to_string(wire_type));
    }

    int64_t parse_zigzag_value()
    {
        switch(wire_type) {
            case WIRETYPE_VARINT: {
                uint64_t value = read_varint();
                return (value >> 1) ^ (- int64_t(value & 1));
            }
            case WIRETYPE_FIXED64:  return read_fixed_width<int64_t>();
            case WIRETYPE_FIXED32:  return read_fixed_width<int32_t>();
        }

        throw std::runtime_error("Can't parse zigzag integral with field type " + std::to_string(wire_type));
    }

    std::string_view parse_bytearray_value()
    {
        if(wire_type != WIRETYPE_LENGTH_DELIMITED) {
            throw std::runtime_error("Can't parse bytearray with field type " + std::to_string(wire_type));
        }

        uint64_t len = read_varint();
        advance_ptr(len);

        return {ptr-len, len};
    }


    bool get_next_field()
    {
        if(ptr == buf_end)  return false;

        uint64_t number = read_varint();
        field_num = (number >> 3);
        wire_type = WireType(number & 7);

        return true;
    }

    void skip_field()
    {
        if (wire_type == WIRETYPE_VARINT) {
            read_varint();
        } else if (wire_type == WIRETYPE_FIXED32) {
            advance_ptr(4);
        } else if (wire_type == WIRETYPE_FIXED64) {
            advance_ptr(8);
        } else if (wire_type == WIRETYPE_LENGTH_DELIMITED) {
            uint64_t len = read_varint();
            advance_ptr(len);
        } else {
            throw std::runtime_error("Unsupported field type " + std::to_string(wire_type));
        }
    }


    template <typename IntegralType>
    void parse_integral_field(IntegralType *field, bool *has_field = nullptr)
    {
        uint64_t value = parse_integer_value();

        *field = IntegralType(value);
        if(has_field)  *has_field = true;
    }

    template <typename RepeatedIntegralType>
    void parse_repeated_integral_field(RepeatedIntegralType *field)
    {
        field->push_back(parse_integer_value());
    }

    template <typename IntegralType>
    void parse_zigzag_field(IntegralType *field, bool *has_field = nullptr)
    {
        int64_t value = parse_zigzag_value();

        *field = IntegralType(value);
        if(has_field)  *has_field = true;
    }

    template <typename RepeatedIntegralType>
    void parse_repeated_zigzag_field(RepeatedIntegralType *field)
    {
        field->push_back(parse_zigzag_value());
    }

    template <typename FloatingPointType>
    void parse_fp_field(FloatingPointType *field, bool *has_field = nullptr)
    {
        *field = parse_fp_value<FloatingPointType>();
        if(has_field)  *has_field = true;
    }

    template <typename RepeatedFloatingPointType>
    void parse_repeated_fp_field(RepeatedFloatingPointType *field)
    {
        using T = typename RepeatedFloatingPointType::value_type;
        field->push_back(parse_fp_value<T>());
    }

    template <typename ByteArrayType>
    void parse_bytearray_field(ByteArrayType *field, bool *has_field = nullptr)
    {
        *field = parse_bytearray_value();
        if(has_field)  *has_field = true;
    }

    template <typename RepeatedByteArrayType>
    void parse_repeated_bytearray_field(RepeatedByteArrayType *field)
    {
        using T = typename RepeatedByteArrayType::value_type;
        field->push_back( T(parse_bytearray_value()));
    }

    template <typename MessageType>
    void parse_message_field(MessageType *field, bool *has_field = nullptr)
    {
        ProtoBufDecoder sub_decoder{parse_bytearray_value()};
        field->ProtoBufDecode(sub_decoder);
        if(has_field)  *has_field = true;
    }

    template <typename RepeatedMessageType>
    void parse_repeated_message_field(RepeatedMessageType *field)
    {
        using T = typename RepeatedMessageType::value_type;

        ProtoBufDecoder sub_decoder{parse_bytearray_value()};
        T value;  value.ProtoBufDecode(sub_decoder);
        field->push_back(std::move(value));
    }
};
