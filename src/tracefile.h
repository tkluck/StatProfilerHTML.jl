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
        typedef struct {
            int revision;
            int version;
            int subversion;
        } PerlVersion_t;

        class TraceFileReader
        {
        public:
            // Note: Constructor does not open the file!
            TraceFileReader(pTHX);
            ~TraceFileReader();

            void open(const std::string &path);
            void close();
            bool is_valid() const { return in; }

            unsigned int get_format_version() const { return file_format_version; }
            const PerlVersion_t& get_source_perl_version() const { return source_perl_version; }
            int get_source_tick_duration() const { return source_tick_duration; }
            int get_source_stack_sample_depth() const { return source_stack_sample_depth; }

            SV *read_trace();
            // Returns the hash of custom meta data records that have been encountered
            // thus far.
            HV *get_custom_metadata();
        private:
            void read_header();
            void read_custom_meta_record(const int size, HV *extra_output_hash = NULL);

            std::FILE *in;
            // TODO maybe introduce a header struct or class for cleanliness?
            unsigned int file_format_version;
            PerlVersion_t source_perl_version;
            int source_tick_duration;
            int source_stack_sample_depth;
            HV *custom_metadata;

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
            long position() const;

            bool is_valid() const { return out; }

            int write_header(unsigned int sampling_interval,
                             unsigned int stack_collect_depth);

            int start_sample(unsigned int weight, OP *current_op);
            int add_frame(unsigned int cxt_type, CV *sub, GV *sub_name, COP *line);
            int end_sample();

            int write_custom_metadata(SV *key, SV *value);

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
