#if SNAPPY

#include "snappy.h"

using namespace devel::statprofiler;
using namespace std;


SnappyInput::SnappyInput(int max_size)
{
    snappy_max = csnappy_max_compressed_length(max_size);
    snappy_input = new char[snappy_max];
    snappy_end = snappy_input;
}

SnappyInput::~SnappyInput()
{
    delete[] snappy_input;
}

int SnappyInput::read(std::FILE *fh, char *buffer, size_t size)
{
    int snappy_read = fread(snappy_end, 1, snappy_input + snappy_max - snappy_end, fh);
    snappy_end += snappy_read;

    if (snappy_end == snappy_input)
        return 0;

    int packet =
        (snappy_input[0] & 0xff) << 8 |
        (snappy_input[1] & 0xff);
    uint32_t decompressed;
    int used = csnappy_get_uncompressed_length(snappy_input + 2, snappy_end - (snappy_input + 2), &decompressed);

    if (used < CSNAPPY_E_OK) {
        warn("Error decoding length for snappy packet: %d", used);
        snappy_end = snappy_input;
        return 0;
    }

    if (decompressed > size) {
        warn("Decompressed packet data would overflow input buffer");
        snappy_end = snappy_input;
        return 0;
    }

    uint32_t bytes = decompressed;
    int ok = csnappy_decompress_noheader(snappy_input + 2 + used, packet - used, buffer, &bytes);

    if (ok < CSNAPPY_E_OK) {
        warn("Error decompressing snappy packet: %d", ok);
        snappy_end = snappy_input;
        return 0;
    }

    size_t remaining = snappy_end - (snappy_input + 2 + packet);
    memmove(snappy_input, snappy_input + 2 + packet, remaining);
    snappy_end = snappy_input + remaining;

    return bytes;
}


SnappyOutput::SnappyOutput(int max_size)
{
    snappy_output = new char[csnappy_max_compressed_length(max_size)];
    snappy_workmem = new char[CSNAPPY_WORKMEM_BYTES];
}

SnappyOutput::~SnappyOutput()
{
    delete[] snappy_output;
    delete[] snappy_workmem;
}

int SnappyOutput::write(FILE *fh, const char *buffer, size_t size)
{
    uint32_t compressed_length;

    csnappy_compress(buffer, size,
                     snappy_output, &compressed_length,
                     snappy_workmem,
                     CSNAPPY_WORKMEM_BYTES_POWER_OF_TWO);

    return
        fputc(compressed_length >> 8, fh) != EOF &&
        fputc(compressed_length & 0xff, fh) != EOF &&
        fwrite(snappy_output, 1, compressed_length, fh) == compressed_length;
}

#endif
