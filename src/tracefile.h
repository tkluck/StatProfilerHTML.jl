#ifndef _DEVEL_STATPROFILER_TRACEFILE
#define _DEVEL_STATPROFILER_TRACEFILE

#include "EXTERN.h"
#include "perl.h"

#include <string>
#include <vector>
#include <cstdio>

#include "thx_member.h"

#define ID_SIZE 6

namespace devel {
    namespace statprofiler {
        struct PerlVersion_t {
            int revision;
            int version;
            int subversion;
        };

        struct Genealogy_t {
            unsigned int id[ID_SIZE], parent_id[ID_SIZE];
            unsigned int ordinal, parent_ordinal;
        };

        enum FrameType
        {
            FRAME_SUB,
            FRAME_XSUB,
            FRAME_MAIN,
            FRAME_EVAL,
        };

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
            const Genealogy_t& get_genealogy_info() const { return genealogy_info; }
            int get_source_tick_duration() const { return source_tick_duration; }
            int get_source_stack_sample_depth() const { return source_stack_sample_depth; }

            SV *read_trace();
            // Returns the hash of custom meta data records that have been encountered
            // thus far.
            HV *get_custom_metadata();

            // Returns the source code that has been collected thus far
            HV *get_source_code();
        private:
            void read_header();
            void read_custom_meta_record(const int size, HV *extra_output_hash = NULL);

            std::FILE *in;
            // TODO maybe introduce a header struct or class for cleanliness?
            unsigned int file_format_version;
            PerlVersion_t source_perl_version;
            Genealogy_t genealogy_info;
            int source_tick_duration;
            int source_stack_sample_depth;
            HV *custom_metadata, *source_code;
            HV *sections;
            // various stashes used by the reader
            HV *st_stash, *sf_stash, *msf_stash, *esf_stash;

            DECL_THX_MEMBER
        };

        class TraceFileWriter
        {
        public:
            // Usage in this order: Construct object, open, write_header, write samples
            TraceFileWriter(pTHX);
            ~TraceFileWriter();

            int open(const std::string &path, bool is_template, unsigned int id[ID_SIZE], unsigned int ordinal);
            void close();
            void shut();
            void flush();
            long position() const;

            bool is_valid() const { return out; }

            int write_header(unsigned int sampling_interval,
                             unsigned int stack_collect_depth,
                             unsigned int id[ID_SIZE], unsigned int ordinal,
                             unsigned int parent_id[ID_SIZE], unsigned int parent_ordinal);

            int start_sample(unsigned int weight, OP *current_op);
            int add_frame(FrameType frame_type, CV *sub, GV *sub_name, COP *line);
            int add_eval_source(SV *eval_text, COP *line);
            int end_sample();

            int write_custom_metadata(SV *key, SV *value);
            int start_section(SV *section_name);
            int end_section(SV *section_name);

        private:
            int write_perl_version();

            std::FILE *out;
            std::string output_file;
            bool force_empty_frame;

            DECL_THX_MEMBER
        };
    }
}

#ifdef _DEVEL_STATPROFILER_XSP
using namespace devel::statprofiler;
#endif

#endif
