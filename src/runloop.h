#ifndef _DEVEL_STATPROFILER_RUNLOOP
#define _DEVEL_STATPROFILER_RUNLOOP

// required because win32_async_check() is not declared as extern "C"
extern "C" {
#include "EXTERN.h"
#include "perl.h"
}

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
        void set_save_source(unsigned int save_source);
        void set_global_metadata(pTHX_ HV *metadata);

        void write_custom_metadata(pTHX_ SV *key, SV *value);
        void start_section(pTHX_ SV *section_name);
        void end_section(pTHX_ SV *section_name);

        bool is_running();

        int get_precision();

        void test_enable();
        double test_hires_usleep(unsigned int usec);
        double test_hires_sleep(double sleep);
        double test_hires_time();
        void test_force_sample(unsigned int increment);
    }
}

namespace devel {
    namespace statprofiler {
        extern double test_hires_usleep(unsigned int usec);
    }
}

#ifdef _DEVEL_STATPROFILER_XSP
using namespace devel::statprofiler;
#endif

#endif
