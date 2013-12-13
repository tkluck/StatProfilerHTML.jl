#ifndef _DEVEL_STATPROFILER_TRACEFILE
#define _DEVEL_STATPROFILER_TRACEFILE

#include "EXTERN.h"
#include "perl.h"

#include <string>
#include <vector>
#include <cstdio>


namespace devel {
    namespace statprofiler {
#if 0 // tentative reader interface
        struct StackFrame
        {
            const char *package;
            const char *subroutine;
            const char *file;
            unsigned int line;
            const char *op_name;
        };

        struct StackTrace
        {
            unsigned int weight;
            std::vector<StackFrame> frames;
        };

        class TraceFileReader
        {
        public:
            TraceFileReader(const std::string &path);
            ~TraceFileReader();

            bool is_valid() const { return in; }
            void close();

            StackTrace read_trace();
        private:
            std::FILE *in;
        };
#endif

        class TraceFileWriter
        {
        public:
            TraceFileWriter(const std::string &path);
            ~TraceFileWriter();

            void open(const std::string &path);
            void close();
            bool is_valid() const { return out; }

            void start_sample(unsigned int weight);
            void add_frame(unsigned int cxt_type, CV *sub, COP *line);
            void add_topmost_op(pTHX_ OP *o);
            void end_sample();

        private:
            std::FILE *out;
            const char *topmost_op_name;
        };
    }
}

#endif
