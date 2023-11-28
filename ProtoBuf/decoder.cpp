#include <string>
#include <iostream>
#include <fstream>
#include <iterator>

#include "ProtoBufDecoder.cpp"


void decoder(std::string_view str, int indent = 0)
{
    ProtoBufDecoder pb(str);
    int field_num, field_type;

    while( pb.get_next_field( &field_num, &field_type))
    {
        switch(field_type)
        {
            case ProtoBufDecoder::FT_LEN: {
                auto str = pb.parse_bytearray_value(field_type);
                if (str.size() > 10) {
                    try {
                        decoder(str, indent+4);
                        break;
                    } catch (const std::exception& e) {
                    }
                }
                printf("%*sSTRING[len=%d] #%d%s%.*s\n", indent, "", str.size(), field_num,
                    (str.size() <= 10? " = ": ""),
                    (str.size() <= 10? str.size() : 0),
                    str.data());
                break;
            }
            default: {
                printf("%*sUNSUPPORTED[type=%d] #%d\n", indent, "", field_type, field_num);
                pb.skip_field( field_type);
            }
        }
    }
}


int main(int argc, char** argv)
{
    if (argc==1)  return 1;

    std::ifstream ifs(argv[1], std::ios::binary);
    std::string str(std::istreambuf_iterator<char>{ifs}, {});
    printf("=== Filesize = %d\n", str.size());

    try {
        decoder(str);
        printf("=== Decoding succeed!\n");
    } catch (const std::exception& e) {
        printf("Internal error: %s\n", e.what());
    }

    return 0;
}
