const char* USAGE =
"Schema-less decoder of arbitrary ProtoBuf messages\n"
"  Usage: decoder file.pbs\n";

#include <string>
#include <cctype>
#include <iostream>
#include <fstream>
#include <iterator>

#include "ProtoBufDecoder.cpp"


bool is_printable_str(std::string_view str)
{
    if (str.size() > 100) {
        return false;
    }

    for (auto c: str) {
        if (! isprint(c)) {
           return false;
        }
    }

    return true;
}


bool decoder(std::string_view str, int indent = 0)
{
    ProtoBufDecoder pb(str);

    while(pb.get_next_field())
    {
        switch(pb.wire_type)
        {
            case ProtoBufDecoder::WIRETYPE_LENGTH_DELIMITED:
            {
                auto str = pb.parse_bytearray_value();
                bool is_printable = is_printable_str(str);

                printf("%*s#%d: STRING[%d]%s%.*s\n",
                    indent, "",
                    pb.field_num,
                    str.size(),
                    (is_printable? " = ": ""),
                    (is_printable? str.size() : 0),
                    str.data());

                if (! is_printable) {
                    try {
                        decoder(str, indent+4);
                        break;
                    } catch (const std::exception& e) {
                    }
                }
                break;
            }

            case ProtoBufDecoder::WIRETYPE_VARINT:
            case ProtoBufDecoder::WIRETYPE_FIXED64:
            case ProtoBufDecoder::WIRETYPE_FIXED32:
            {
                const char* str_type =
                    (pb.wire_type == ProtoBufDecoder::WIRETYPE_FIXED64? "I64" :
                     pb.wire_type == ProtoBufDecoder::WIRETYPE_FIXED32? "I32" :
                     "VARINT"
                    );
                int64_t value = pb.parse_integer_value();
                printf("%*s#%d: %s = %lld\n", indent, "", pb.field_num, str_type, value);
                break;
            }

            default:  return false;
        }
    }

    return true;
}


int main(int argc, char** argv)
{
    if (argc != 2) {
        printf(USAGE);
        return 1;
    }

    std::ifstream ifs(argv[1], std::ios::binary);
    std::string str(std::istreambuf_iterator<char>{ifs}, {});

    try {
        printf("=== Filesize = %d\n", str.size());
        decoder(str);
        printf("=== Decoding succeed!\n");
    } catch (const std::exception& e) {
        printf("Internal error: %s\n", e.what());
    }

    return 0;
}
