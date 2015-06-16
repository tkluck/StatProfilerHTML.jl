#include "tracecollector.h"
#include "tracefile.h"

using namespace devel::statprofiler;

extern MGVTBL Devel_StatProfiler_eval_idx_vtbl;


// needs to be kept in sync with S_dopoptosub in pp_ctl.c
STATIC I32
S_dopoptosub_at(pTHX_ const PERL_CONTEXT *cxstk, I32 startingblock)
{
    dVAR;
    I32 i;

    for (i = startingblock; i >= 0; i--) {
	const PERL_CONTEXT * const cx = &cxstk[i];
	switch (CxTYPE(cx)) {
	default:
	    continue;
	case CXt_SUB:
            /* in sub foo { /(?{...})/ }, foo ends up on the CX stack
             * twice; the first for the normal foo() call, and the second
             * for a faked up re-entry into the sub to execute the
             * code block. Hide this faked entry from the world. */
#if PERL_VERSION >= 18
            if (cx->cx_type & CXp_SUB_RE_FAKE)
                continue;
#endif
	case CXt_EVAL:
	case CXt_FORMAT:
	    DEBUG_l( Perl_deb(aTHX_ "(dopoptosub_at(): found sub at cx=%ld)\n", (long)i));
	    return i;
	}
    }
    return i;
}


// needs to be kept in sync with Perl_caller_cx in op.c
void
devel::statprofiler::collect_trace(pTHX_ TraceFileWriter &trace, int depth, bool eval_source)
{
    I32 cxix = S_dopoptosub_at(aTHX_ cxstack, cxstack_ix);
    const PERL_CONTEXT *ccstack = cxstack;
    const PERL_SI *top_si = PL_curstackinfo;
    CV *db_sub = PL_DBsub ? GvCV(PL_DBsub) : NULL;
    COP *line = PL_curcop;
    bool previous_is_eval_block = false;

    for (;;) {
        // skip over auxiliary stacks pushed by PUSHSTACKi
        while (cxix < 0 && top_si->si_type != PERLSI_MAIN) {
            top_si = top_si->si_prev;
            ccstack = top_si->si_cxstack;
            cxix = S_dopoptosub_at(aTHX_ ccstack, top_si->si_cxix);
        }
        if (cxix < 0)
            break;
        // do not report the automatic calls to &DB::sub
        if (!(db_sub && cxix >= 0 &&
              ccstack[cxix].blk_sub.cv == GvCV(PL_DBsub))) {
            const PERL_CONTEXT *sub = &ccstack[cxix];
            const PERL_CONTEXT *caller = sub;

            if (db_sub) {
                // when there is a &DB::sub, we need its call site to get
                // the correct file/line information
                I32 dbcxix = S_dopoptosub_at(aTHX_ ccstack, cxix - 1);

                if (dbcxix >= 0 && ccstack[dbcxix].blk_sub.cv == db_sub) {
                    caller = &ccstack[dbcxix];
                    cxix = dbcxix;
                }
            }

            // when called between an entersub and the following nextstate,
            // ignore the set-up but-not-entered-yet stack frame
            // also ignore the call frame set up for BEGIN blocks
            bool is_eval_block = CxTRYBLOCK(sub);
            if ((line != caller->blk_oldcop ||
                        CxTYPE(sub) != CXt_SUB ||
                        PL_op != CvSTART(sub->blk_sub.cv)) &&
                    line != &PL_compiling &&
                    !is_eval_block) {
                if (CxTYPE(sub) != CXt_EVAL) {
                    trace.add_frame(FRAME_SUB, sub->blk_sub.cv, NULL, line);
                } else if (CxOLD_OP_TYPE(sub) != OP_ENTEREVAL) {
                    trace.add_frame(FRAME_MAIN, NULL, NULL, line);
                } else {
                    if (eval_source) {
                        SV *eval_text = sub->blk_eval.cur_text;
                        MAGIC *marker = SvMAGICAL(eval_text) ? mg_findext(eval_text, PERL_MAGIC_ext, &Devel_StatProfiler_eval_idx_vtbl) : NULL;

                        if (marker) {
                            EvalCollected *collected = (EvalCollected *) marker->mg_ptr;

                            if (!collected->saved) {
                                trace.add_eval_source(eval_text, collected->evalseq);
                                collected->saved = true;
                            }
                        }
                    }

                    trace.add_frame(FRAME_EVAL, NULL, NULL, line);
                }
            }
            else
                ++depth;
            if (!is_eval_block)
                line = caller->blk_oldcop;

            previous_is_eval_block = is_eval_block;
            if (!--depth)
                break;
        }
        cxix = S_dopoptosub_at(aTHX_ ccstack, cxix - 1);
    }

    // report main, but ignore the stack frame set up for BEGIN blocks
    if (depth && line != &PL_compiling)
        trace.add_frame(FRAME_MAIN, NULL, NULL, line);
}

MGVTBL Devel_StatProfiler_eval_idx_vtbl;
