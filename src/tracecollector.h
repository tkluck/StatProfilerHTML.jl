#ifndef _DEVEL_STATPROFILER_TRACECOLLECTOR
#define _DEVEL_STATPROFILER_TRACECOLLECTOR

#include "EXTERN.h"
#include "perl.h"

namespace devel {
    namespace statprofiler {
        void collect_trace(pTHX_ int depth);
    }
}

#endif
