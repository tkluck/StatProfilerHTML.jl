#ifndef _DEVEL_STATPROFILER_TRACEFILE
#define _DEVEL_STATPROFILER_TRACEFILE

#include "EXTERN.h"
#include "perl.h"

#include <string>
#include <vector>
#include <cstdio>

#include "thx_member.h"

#define ID_SIZE 6
// bigger buffers compress better
#if SNAPPY
    #define OUTPUT_BUFFER_SIZE 32000
#else
    #define OUTPUT_BUFFER_SIZE 8192
#endif

namespace devel {
    namespace statprofiler {
        struct PerlVersion_t {
            int revision;
            int version;
            int subversion;
        };

        struct Genealogy_t {
            char id[ID_SIZE * 4 * 2], parent_id[ID_SIZE * 4 * 2];
            unsigned int ordinal, parent_ordinal;
        };

        enum FrameType
        {
            FRAME_SUB,
            FRAME_XSUB,
            FRAME_MAIN,
            FRAME_EVAL,
        };

        class SnappyInput;
        class SnappyOutput;

        class InputBuffer
        {
        public:
            InputBuffer();
            ~InputBuffer();

            void skip_bytes(size_t size);
            int read_byte();
            void read_bytes(void *buffer, size_t size);

            bool is_valid() const { return fh; }

            void open(std::FILE *fh);
            void close();

            int read_raw_byte();
            bool read_raw_bytes(void *buffer, size_t size);

        private:
            void fill_buffer();

#if SNAPPY
            SnappyInput *snappy;
#endif
            std::FILE *fh;
            char input_buffer[OUTPUT_BUFFER_SIZE];
            char *input_position, *input_end;
        };

        class OutputBuffer
        {
        public:
            OutputBuffer();
            ~OutputBuffer();

            int write_bytes(const void *bytes, size_t size);
            int write_byte(const char byte);
            int flush();

            bool is_valid() const { return fh; }

            void open(std::FILE *fh);
            void close();

            int position() const;

            bool write_raw_byte(int c);
            bool write_raw_bytes(const void *buffer, size_t size);

        private:
            int flush_buffer();

#if SNAPPY
            SnappyOutput *snappy;
#endif
            std::FILE *fh;
            char output_buffer[OUTPUT_BUFFER_SIZE];
            char *output_position;
        };

        class TraceFileReader
        {
        public:
            // Note: Constructor does not open the file!
            TraceFileReader(pTHX);
            ~TraceFileReader();

            void open(const std::string &path);
            void close();
            bool is_valid() const { return in.is_valid(); }

            unsigned int get_format_version() const { return file_format_version; }
            const PerlVersion_t& get_source_perl_version() const { return source_perl_version; }
            const Genealogy_t& get_genealogy_info() const { return genealogy_info; }
            int get_source_tick_duration() const { return source_tick_duration; }
            int get_source_stack_sample_depth() const { return source_stack_sample_depth; }

            SV *read_trace();
            // Returns the hash of custom meta data records that have been encountered
            // thus far.
            HV *get_custom_metadata();
            void clear_custom_metadata();

            // Returns the source code that has been collected thus far
            HV *get_source_code();

            // Returns currently-open sections
            HV *get_active_sections();

            bool is_file_ended() const { return file_ended; }
            bool is_stream_ended() const { return stream_ended; }

        private:
            void read_header();
            void read_custom_meta_record(const int size, HV *extra_output_hash = NULL);

            InputBuffer in;
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
            bool sections_changed, metadata_changed;
            bool stream_ended, file_ended;

            DECL_THX_MEMBER
        };

        class TraceFileWriter
        {
        public:
            static const bool write_end_tag = true;

            // Usage in this order: Construct object, open, write_header, write samples
            TraceFileWriter(pTHX);
            ~TraceFileWriter();

            int open(const std::string &path, bool is_template, uint32_t id[ID_SIZE], unsigned int ordinal);
            void close(bool write_end_tag = false);
            void shut();
            void flush();
            long position() const;

            bool is_valid() const { return out.is_valid(); }

            int write_header(unsigned int sampling_interval,
                             unsigned int stack_collect_depth,
                             uint32_t id[ID_SIZE], unsigned int ordinal,
                             uint32_t parent_id[ID_SIZE], unsigned int parent_ordinal);

            int start_sample(unsigned int weight, OP *current_op);
            int add_frame(FrameType frame_type, CV *sub, GV *sub_name, COP *line);
            int add_eval_source(SV *eval_text, COP *line, U32 eval_seq);
            int end_sample();

            int write_custom_metadata(SV *key, SV *value);
            int start_section(SV *section_name);
            int end_section(SV *section_name);

        private:
            int write_perl_version();

            OutputBuffer out;
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
