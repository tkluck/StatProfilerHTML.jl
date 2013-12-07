#ifndef _DEVEL_STATPROFILER_RUNLOOP
#define _DEVEL_STATPROFILER_RUNLOOP

#include "EXTERN.h"
#include "perl.h"

namespace devel {
    namespace statprofiler {
        void init_runloop(pTHX);
        void clone_runloop(pTHX);
        int runloop(pTHX);
    }
}

#ifdef _DEVEL_STATPROFILER_XSP
using namespace devel::statprofiler;
#endif

#endif
