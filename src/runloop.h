#ifndef _DEVEL_STATPROFILER_RUNLOOP
#define _DEVEL_STATPROFILER_RUNLOOP

#include "EXTERN.h"
#include "perl.h"

namespace devel {
    namespace statprofiler {
        void init_runloop(pTHX);
        void clone_runloop(pTHX);
        void install_runloop();

        void set_enabled(bool enabled);
        void set_output_file(const char *path, bool is_template);
        void set_sampling_interval(unsigned int interval);
        void set_stack_collection_depth(unsigned int num_stack_frames);
        void set_max_output_file_size(size_t max_size);

        void write_custom_metadata(pTHX_ SV *key, SV *value);
        void start_section(pTHX_ SV *section_name);
        void end_section(pTHX_ SV *section_name);

        int get_precision();
    }
}

#ifdef _DEVEL_STATPROFILER_XSP
using namespace devel::statprofiler;
#endif

#endif
