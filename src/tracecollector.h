#ifndef _DEVEL_STATPROFILER_TRACECOLLECTOR
#define _DEVEL_STATPROFILER_TRACECOLLECTOR

#include "EXTERN.h"
#include "perl.h"

namespace devel {
    namespace statprofiler {
        class TraceFileWriter;

        void collect_trace(pTHX_ TraceFileWriter &trace, int depth, bool eval_source);
    }
}

#endif
