#ifndef _DEVEL_STATPROFILER_SNAPPY
#define _DEVEL_STATPROFILER_SNAPPY

#include <EXTERN.h>
#include <perl.h>

#if defined(_WIN32)
#include "wincompat.h"
#endif

#include <snappy/csnappy.h>

#include <cstdio>


namespace devel {
    namespace statprofiler {
        class SnappyInput
        {
        public:
            SnappyInput(int max_size);
            ~SnappyInput();

            int read(std::FILE *fh, char *buffer, size_t size);

        private:
            char *snappy_input, *snappy_end;
            int snappy_max;
        };

        class SnappyOutput
        {
        public:
            SnappyOutput(int max_size);
            ~SnappyOutput();

            int write(std::FILE *fh, const char *buffer, size_t size);

        private:
            char *snappy_output;
            char *snappy_workmem;
        };
    }
}

#endif

