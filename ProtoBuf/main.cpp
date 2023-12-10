#include "ProtoBufEncoder.cpp"
#include "ProtoBufDecoder.cpp"
#include "Example.pb.cpp"


// Fill msg with some data
MainMessage make_message()
{
    MainMessage msg;

    msg.opt_uint32   = 101;
    msg.req_sfixed64 = -102;
    msg.opt_double   = 103.14;
    msg.req_bytes    = "104";

    msg.req_msg.req_int64    = -201;
    msg.req_msg.opt_sint32   = -202;
    msg.req_msg.req_uint64   = 203;
    msg.req_msg.opt_fixed32  = 204;
    msg.req_msg.req_float    = -205.42;
    msg.req_msg.opt_string   = "206";

    return msg;
}


// Compare two message records and return the name of the first unequal field found,
// or nullptr if records are equal
const char* compare(MainMessage& msg1, MainMessage& msg2)
{
    if (msg1.opt_uint32   != msg2.opt_uint32  )  return "opt_uint32";
    if (msg1.req_sfixed64 != msg2.req_sfixed64)  return "req_sfixed64";
    if (msg1.opt_double   != msg2.opt_double  )  return "opt_double";
    if (msg1.req_bytes    != msg2.req_bytes   )  return "req_bytes";

    if (msg1.req_msg.req_int64   != msg2.req_msg.req_int64  )  return "req_msg.req_int64";
    if (msg1.req_msg.opt_sint32  != msg2.req_msg.opt_sint32 )  return "req_msg.opt_sint32";
    if (msg1.req_msg.req_uint64  != msg2.req_msg.req_uint64 )  return "req_msg.req_uint64";
    if (msg1.req_msg.opt_fixed32 != msg2.req_msg.opt_fixed32)  return "req_msg.opt_fixed32";
    if (msg1.req_msg.req_float   != msg2.req_msg.req_float  )  return "req_msg.req_float";
    if (msg1.req_msg.opt_string  != msg2.req_msg.opt_string )  return "req_msg.opt_string";

    return nullptr;
}


int main()
{
    try {
        MainMessage orig_msg = make_message(), decoded_msg;

        // Encode message into string buffer
        ProtoBufEncoder encoder;
        orig_msg.ProtoBufEncode(encoder);
        std::string buffer = encoder.result();

        // Decode message from the buffer
        ProtoBufDecoder decoder(buffer);
        decoded_msg.ProtoBufDecode(decoder);

        // Check whether the decoded message is the same as the original
        auto error = compare(orig_msg, decoded_msg);
        if (error) {
            printf("Incorrectly restored field: %s\n", error);
        } else {
            printf("Data restored correctly!\n");
        }

    } catch (const std::exception& e) {
        printf("Internal error: %s\n", e.what());
    }
    return 0;
}
