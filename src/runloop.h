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

        void write_custom_metadata(SV *key, SV *value);
    }
}

#ifdef _DEVEL_STATPROFILER_XSP
using namespace devel::statprofiler;
#endif

#endif
