#ifndef _DEVEL_STATPROFILER_TRACECOLLECTOR
#define _DEVEL_STATPROFILER_TRACECOLLECTOR

#include "EXTERN.h"
#include "perl.h"

namespace devel {
    namespace statprofiler {
        class TraceFileWriter;

        struct EvalCollected {
            U32 sub_gen;
            U32 evalseq;
            bool saved;

            EvalCollected(pTHX) :
                sub_gen(PL_breakable_sub_gen),
                evalseq(PL_evalseq),
                saved(false)
            { }
        };

        void collect_trace(pTHX_ TraceFileWriter &trace, int depth, bool eval_source);
    }
}

#endif
