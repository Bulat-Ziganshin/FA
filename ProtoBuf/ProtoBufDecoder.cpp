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


template <typename MessageType>
inline MessageType ProtoBufDecode(std::string_view buffer)
{
    MessageType msg;
    msg.ProtoBufDecode(buffer);
    return msg;
}


struct ProtoBufDecoder
{
    enum WireType
    {
      WIRETYPE_UNDEFINED = -1,
      WIRETYPE_VARINT = 0,
      WIRETYPE_FIXED64 = 1,
      WIRETYPE_LENGTH_DELIMITED = 2,
      WIRETYPE_START_GROUP = 3,
      WIRETYPE_END_GROUP = 4,
      WIRETYPE_FIXED32 = 5,
    };

    const char* ptr = nullptr;
    const char* buf_end = nullptr;
    uint32_t field_num = -1;
    WireType wire_type = WIRETYPE_UNDEFINED;


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

    bool eof()
    {
        return(ptr >= buf_end);
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
            if(eof())        throw std::runtime_error("Unexpected end of buffer in varint");
            if(shift >= 64)  throw std::runtime_error("More than 10 bytes in varint");

            byte = *(uint8_t*)ptr;
            value |= ((byte & 127) << shift);
            ptr++;  shift += 7;
        }
        while(byte & 128);

        return value;
    }

    int64_t read_zigzag()
    {
        uint64_t value = read_varint();
        return (value >> 1) ^ (- int64_t(value & 1));
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
            case WIRETYPE_VARINT:   return read_zigzag();
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
        if(eof())  return false;

        uint64_t number = read_varint();
        field_num = (number / 8);
        wire_type = WireType(number % 8);

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


#define define_readers(TYPE, C_TYPE, PARSER, READER)                                                               \
                                                                                                                   \
    C_TYPE get_##TYPE()                                                                                            \
    {                                                                                                              \
        using FieldType = C_TYPE;                                                                                  \
        return FieldType(PARSER());                                                                                \
    }                                                                                                              \
                                                                                                                   \
    template <typename FieldType>                                                                                  \
    void get_##TYPE(FieldType *field, bool *has_field = nullptr)                                                   \
    {                                                                                                              \
        *field = FieldType(PARSER());                                                                              \
        if(has_field)  *has_field = true;                                                                          \
    }                                                                                                              \
                                                                                                                   \
    template <typename RepeatedFieldType>                                                                          \
    void get_repeated_##TYPE(RepeatedFieldType *field)                                                             \
    {                                                                                                              \
        using FieldType = typename RepeatedFieldType::value_type;                                                  \
                                                                                                                   \
        if(std::is_scalar<C_TYPE>()  &&  (wire_type == WIRETYPE_LENGTH_DELIMITED)) {                               \
            /* Parsing packed repeated field */                                                                    \
            ProtoBufDecoder decoder(parse_bytearray_value());                                                      \
            while(! decoder.eof()) {                                                                               \
                field->push_back( FieldType(decoder.READER()) );                                                   \
            }                                                                                                      \
        } else {                                                                                                   \
            field->push_back( FieldType(PARSER()) );                                                               \
        }                                                                                                          \
    }                                                                                                              \


    define_readers(int32, int32_t, parse_integer_value, read_varint)
    define_readers(int64, int64_t, parse_integer_value, read_varint)
    define_readers(uint32, uint32_t, parse_integer_value, read_varint)
    define_readers(uint64, uint64_t, parse_integer_value, read_varint)

    define_readers(sfixed32, int32_t, parse_integer_value, read_fixed_width<int32_t>)
    define_readers(sfixed64, int64_t, parse_integer_value, read_fixed_width<int64_t>)
    define_readers(fixed32, uint32_t, parse_integer_value, read_fixed_width<uint32_t>)
    define_readers(fixed64, uint64_t, parse_integer_value, read_fixed_width<uint64_t>)

    define_readers(sint32, int32_t, parse_zigzag_value, read_zigzag)
    define_readers(sint64, int64_t, parse_zigzag_value, read_zigzag)

    define_readers(bool, bool, parse_integer_value, read_varint)
    define_readers(enum, int32_t, parse_integer_value, read_varint)

    define_readers(float, float, parse_fp_value<FieldType>, read_fixed_width<float>)
    define_readers(double, double, parse_fp_value<FieldType>, read_fixed_width<double>)

    define_readers(string, std::string_view, parse_bytearray_value, parse_bytearray_value)
    define_readers(bytes, std::string_view, parse_bytearray_value, parse_bytearray_value)

    template <typename MessageType>
    void get_message(MessageType *field, bool *has_field = nullptr)
    {
        field->ProtoBufDecode(parse_bytearray_value());
        if(has_field)  *has_field = true;
    }

    template <typename RepeatedMessageType>
    void get_repeated_message(RepeatedMessageType *field)
    {
        using T = typename RepeatedMessageType::value_type;
        field->push_back( ProtoBufDecode<T>(parse_bytearray_value()));
    }
};
