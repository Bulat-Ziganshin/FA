#include <string>
#include <cstring>
#include <cstdint>
#include <stdexcept>


struct ProtoBufEncoder
{
    enum {
        MAX_VARINT_SIZE = (64+6)/7,  // number of 7-bit chunks in 64-bit int
        MAX_LENGTH_CODE_SIZE = (32+6)/7,  // number of 7-bit chunks in 32-bit int encoding message length
    };

    enum WireType
    {
      WIRETYPE_VARINT = 0,
      WIRETYPE_FIXED64 = 1,
      WIRETYPE_LENGTH_DELIMITED = 2,
      WIRETYPE_START_GROUP = 3,
      WIRETYPE_END_GROUP = 4,
      WIRETYPE_FIXED32 = 5,
    };

    std::string buffer;
    char* ptr;
    char* buf_end;


    ProtoBufEncoder()
    {
        ptr = buf_end = buffer.data();
    }

    std::string result()
    {
        buffer.resize(pos());
        buffer.shrink_to_fit();

        std::string temp_buffer;
        std::swap(buffer, temp_buffer);
        ptr = buf_end = buffer.data();

        return temp_buffer;
    }

    size_t pos()
    {
        return ptr - buffer.data();
    }

    char* advance_ptr(int bytes)
    {
        if(buf_end - ptr < bytes)
        {
            auto old_pos = pos();
            buffer.resize(buffer.size()*2 + bytes);
            ptr = buffer.data() + old_pos;
            buf_end = buffer.data() + buffer.size();
        }
        ptr += bytes;
        return ptr - bytes;
    }


    template <typename FixedType>
    void write_fixed_width(FixedType value)
    {
        auto old_ptr = advance_ptr(sizeof(value));
        memcpy(old_ptr, &value, sizeof(value));  // TODO: reverse byte order on big-endian cpus
    }

    void write_varint(uint64_t value)
    {
        ptr = advance_ptr(MAX_VARINT_SIZE);  // reserve enough space

        while(value >= 128) {
            *ptr++ = (value & 127) | 128;
            value /= 128;
        }
        *ptr++ = value;
    }

    void write_varint_at(size_t varint_pos, size_t varint_size, uint64_t value)
    {
        auto ptr = buffer.data() + varint_pos;
        for (int i = 1; i < varint_size; ++i)
        {
            *ptr++ = (value & 127) | 128;
            value /= 128;
        }
        *ptr++ = value;
    }

    void write_zigzag(int64_t value)
    {
        uint64_t x = value;
        write_varint((x << 1) ^ (- int64_t(x >> 63)));
    }

    void write_bytearray(std::string_view value)
    {
        write_varint(value.size());
        auto old_ptr = advance_ptr(value.size());
        memcpy(old_ptr, value.data(), value.size());
    }

    void write_field_tag(uint32_t field_num, WireType wire_type)
    {
        write_varint(field_num*8 + wire_type);
    }

    // Start a length-delimited field with yet unknown size and return its start_pos
    size_t start_length_delimited()
    {
        advance_ptr(MAX_LENGTH_CODE_SIZE);
        return pos();
    }

    // Finish a length-delimited field and fill its length with now-known value
    void commit_length_delimited(size_t start_pos)
    {
        size_t field_len = pos() - start_pos;
        write_varint_at(start_pos - MAX_LENGTH_CODE_SIZE, MAX_LENGTH_CODE_SIZE, field_len);
    }

    template <typename Lambda>
    void write_length_delimited(Lambda code)
    {
        auto start_pos = start_length_delimited();
        code();
        commit_length_delimited(start_pos);
    }


#define define_writers(TYPE, C_TYPE, WIRETYPE, WRITER)                                                             \
                                                                                                                   \
    void put_##TYPE(uint32_t field_num, C_TYPE value)                                                              \
    {                                                                                                              \
        write_field_tag(field_num, WIRETYPE);                                                                      \
        WRITER(value);                                                                                             \
    }                                                                                                              \
                                                                                                                   \
    template <typename FieldType>                                                                                  \
    void put_repeated_##TYPE(uint32_t field_num, FieldType&& value)                                                \
    {                                                                                                              \
        for(auto &x: value)  put_##TYPE(field_num, x);                                                             \
    }                                                                                                              \
                                                                                                                   \
    template <typename FieldType>                                                                                  \
    void put_packed_##TYPE(uint32_t field_num, FieldType&& value)                                                  \
    {                                                                                                              \
        static_assert(std::is_scalar<C_TYPE>(),                                                                    \
            "put_packed_" #TYPE " isn't defined according to ProtoBuf format specifications");                     \
                                                                                                                   \
        write_field_tag(field_num, WIRETYPE_LENGTH_DELIMITED);                                                     \
        write_length_delimited([&]{ for(auto &x: value)  WRITER(x); });                                            \
    }                                                                                                              \


    define_writers(int32, int32_t, WIRETYPE_VARINT, write_varint)
    define_writers(int64, int64_t, WIRETYPE_VARINT, write_varint)
    define_writers(uint32, uint32_t, WIRETYPE_VARINT, write_varint)
    define_writers(uint64, uint64_t, WIRETYPE_VARINT, write_varint)

    define_writers(sfixed32, int32_t, WIRETYPE_FIXED32, write_fixed_width)
    define_writers(sfixed64, int64_t, WIRETYPE_FIXED64, write_fixed_width)
    define_writers(fixed32, uint32_t, WIRETYPE_FIXED32, write_fixed_width)
    define_writers(fixed64, uint64_t, WIRETYPE_FIXED64, write_fixed_width)

    define_writers(sint32, int32_t, WIRETYPE_VARINT, write_zigzag)
    define_writers(sint64, int64_t, WIRETYPE_VARINT, write_zigzag)

    define_writers(bool, bool, WIRETYPE_VARINT, write_varint)
    define_writers(enum, int32_t, WIRETYPE_VARINT, write_varint)

    define_writers(float, float, WIRETYPE_FIXED32, write_fixed_width)
    define_writers(double, double, WIRETYPE_FIXED64, write_fixed_width)

    define_writers(string, std::string_view, WIRETYPE_LENGTH_DELIMITED, write_bytearray)
    define_writers(bytes, std::string_view, WIRETYPE_LENGTH_DELIMITED, write_bytearray)

    template <typename FieldType>
    void put_message(uint32_t field_num, FieldType&& value)
    {
        write_field_tag(field_num, WIRETYPE_LENGTH_DELIMITED);
        write_length_delimited([&]{ value.ProtoBufEncode(*this); });
    }

    template <typename FieldType>
    void put_repeated_message(uint32_t field_num, FieldType&& value)
    {
        for(auto &x: value)  put_message(field_num, x);
    }
};


template <typename MessageType>
inline std::string ProtoBufEncode(MessageType&& msg)
{
    ProtoBufEncoder pb;
    msg.ProtoBufEncode(pb);
    return pb.result();
}
