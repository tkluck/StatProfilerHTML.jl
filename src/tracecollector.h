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

            EvalCollected(U32 _sub_gen, U32 _evalseq) :
                sub_gen(_sub_gen),
                evalseq(_evalseq),
                saved(false)
            { }
        };

        void collect_trace(pTHX_ TraceFileWriter &trace, int depth, bool eval_source);
        EvalCollected *get_or_attach_evalcollected(pTHX_ SV *eval_text);
    }
}

#endif
