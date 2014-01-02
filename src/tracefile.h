#ifndef _DEVEL_STATPROFILER_TRACEFILE
#define _DEVEL_STATPROFILER_TRACEFILE

#include "EXTERN.h"
#include "perl.h"

#include <string>
#include <vector>
#include <cstdio>


namespace devel {
    namespace statprofiler {
        class TraceFileReader
        {
        public:
            TraceFileReader(const std::string &path);
            ~TraceFileReader();

            void open(const std::string &path);
            void close();
            bool is_valid() const { return in; }

            unsigned int version() const { return file_version; }

            SV *read_trace();
        private:
            std::FILE *in;
            unsigned int file_version;
        };

        class TraceFileWriter
        {
        public:
            TraceFileWriter(const std::string &path, bool is_template);
            ~TraceFileWriter();

            void open(const std::string &path, bool is_template);
            void close();
            bool is_valid() const { return out; }

            void start_sample(pTHX_ unsigned int weight, OP *current_op);
            void add_frame(unsigned int cxt_type, CV *sub, GV *sub_name, COP *line);
            void end_sample();

        private:
            std::FILE *out;
            std::string output_file;
            unsigned int seed;
        };
    }
}

#ifdef _DEVEL_STATPROFILER_XSP
using namespace devel::statprofiler;
#endif

#endif
