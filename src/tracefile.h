#ifndef _DEVEL_STATPROFILER_TRACEFILE
#define _DEVEL_STATPROFILER_TRACEFILE

#include "EXTERN.h"
#include "perl.h"

#include <string>
#include <vector>
#include <cstdio>

#include "thx_member.h"

namespace devel {
    namespace statprofiler {
        class TraceFileReader
        {
        public:
            // Note: Constructor does not open the file!
            TraceFileReader(pTHX);
            ~TraceFileReader();

            void open(const std::string &path);
            void close();
            bool is_valid() const { return in; }

            unsigned int version() const { return file_version; }

            SV *read_trace();
        private:
            void read_header();

            std::FILE *in;
            unsigned int file_version;
            DECL_THX_MEMBER
        };

        class TraceFileWriter
        {
        public:
            // Usage in this order: Construct object, open, write_header, write samples
            TraceFileWriter(pTHX_ const std::string &path, bool is_template);
            ~TraceFileWriter();

            int open(const std::string &path, bool is_template);
            void close();
            bool is_valid() const { return out; }

            int write_header(unsigned int sampling_interval,
                             unsigned int stack_collect_depth);

            int start_sample(unsigned int weight, OP *current_op);
            int add_frame(unsigned int cxt_type, CV *sub, GV *sub_name, COP *line);
            int end_sample();

        private:
            int write_perl_version();

            std::FILE *out;
            std::string output_file;
            unsigned int seed;
            DECL_THX_MEMBER
        };
    }
}

#ifdef _DEVEL_STATPROFILER_XSP
using namespace devel::statprofiler;
#endif

#endif
