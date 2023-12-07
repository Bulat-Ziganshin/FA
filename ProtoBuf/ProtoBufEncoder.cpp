#include <string>
#include <cstring>
#include <cstdint>
#include <stdexcept>


struct ProtoBufEncoder
{
    const int MAX_VARINT_SIZE = (64+6)/7;  // number of 7-bit chunks in 64-bit int

    enum WireType
    {
      WIRETYPE_VARINT = 0,
      WIRETYPE_FIXED64 = 1,
      WIRETYPE_LENGTH_DELIMITED = 2,
      WIRETYPE_START_GROUP = 3,
      WIRETYPE_END_GROUP = 4,
      WIRETYPE_FIXED32 = 5,
    };

    std::string str;
    char* ptr = nullptr;
    char* buf_end = nullptr;


    std::string result()
    {
        str.resize(pos());
        str.shrink_to_fit();
        ptr = buf_end = nullptr;
        return std::move(str);
    }

    size_t pos()
    {
        return ptr - str.data();
    }

    char* advance_ptr(int bytes)
    {
        if(buf_end - ptr < bytes)
        {
            auto old_pos = pos();
            str.resize(str.size()*2 + bytes);
            ptr = str.data() + old_pos;
            buf_end = str.data() + str.size();
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

    void write_maxlen_varint_at(size_t pos, uint64_t value)
    {
        auto ptr = str.data() + pos;
        for (int i = 0; i < MAX_VARINT_SIZE - 1; ++i)
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
        advance_ptr(MAX_VARINT_SIZE);
        return pos();
    }

    // Finish a length-delimited field and fill its length with now-known value
    void commit_length_delimited(size_t start_pos)
    {
        size_t field_len = pos() - start_pos;
        write_maxlen_varint_at(start_pos - MAX_VARINT_SIZE, field_len);
    }

    template <typename Lambda>
    void write_length_delimited(Lambda code)
    {
        auto start_pos = start_length_delimited();
        code();
        commit_length_delimited(start_pos);
    }


    template <typename FieldType>
    void write_fixed_width_field(uint32_t field_num, FieldType value)
    {
        WireType wire_type =
            sizeof(FieldType) == 4? WIRETYPE_FIXED32 :
            sizeof(FieldType) == 8? WIRETYPE_FIXED64 :
                                    throw std::runtime_error("Unsupported field type in write_fixed_width_field");

        write_field_tag(field_num, wire_type);
        write_fixed_width(value);
    }

    template <typename FieldType>
    void write_varint_field(uint32_t field_num, FieldType value)
    {
        write_field_tag(field_num, WIRETYPE_VARINT);
        write_varint(value);
    }

    template <typename FieldType>
    void write_zigzag_field(uint32_t field_num, FieldType value)
    {
        write_field_tag(field_num, WIRETYPE_VARINT);
        write_zigzag(value);
    }

    void write_bytearray_field(uint32_t field_num, std::string_view value)
    {
        write_field_tag(field_num, WIRETYPE_LENGTH_DELIMITED);
        write_bytearray(value);
    }

    template <typename FieldType>
    void write_message_field(uint32_t field_num, FieldType&& value)
    {
        write_field_tag(field_num, WIRETYPE_LENGTH_DELIMITED);
        write_length_delimited([&]{ value.ProtoBufEncode(*this); });
    }


    template <typename FieldType>
    void write_repeated_fixed_width_field(uint32_t field_num, FieldType&& value)
    {
        for(auto &x: value)  write_fixed_width_field(field_num, x);
    }

    template <typename FieldType>
    void write_repeated_varint_field(uint32_t field_num, FieldType&& value)
    {
        for(auto &x: value)  write_varint_field(field_num, x);
    }

    template <typename FieldType>
    void write_repeated_zigzag_field(uint32_t field_num, FieldType&& value)
    {
        for(auto &x: value)  write_zigzag_field(field_num, x);
    }

    template <typename FieldType>
    void write_repeated_bytearray_field(uint32_t field_num, FieldType&& value)
    {
        for(auto &x: value)  write_bytearray_field(field_num, x);
    }

    template <typename FieldType>
    void write_repeated_message_field(uint32_t field_num, FieldType&& value)
    {
        for(auto &x: value)  write_message_field(field_num, x);
    }
};
