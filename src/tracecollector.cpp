#include "tracecollector.h"
#include "tracefile.h"

using namespace devel::statprofiler;


// needs to be kept in sync with S_dopoptosub in op.c
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
#if PERL_SUBVERSION >= 18
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
devel::statprofiler::collect_trace(pTHX_ TraceFileWriter &trace, int depth)
{
    I32 cxix = S_dopoptosub_at(aTHX_ cxstack, cxstack_ix);
    const PERL_CONTEXT *ccstack = cxstack;
    const PERL_SI *top_si = PL_curstackinfo;
    CV *db_sub = PL_DBsub ? GvCV(PL_DBsub) : NULL;
    COP *line = PL_curcop;

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
            if (line != caller->blk_oldcop && line != &PL_compiling) {
                if (CxTYPE(sub) != CXt_EVAL)
                    trace.add_frame(CxTYPE(sub), sub->blk_sub.cv, line);
                else
                    trace.add_frame(CxTYPE(sub), NULL, line);
            }
            else
                ++depth;
            line = caller->blk_oldcop;

            if (!--depth)
                break;
        }
        cxix = S_dopoptosub_at(aTHX_ ccstack, cxix - 1);
    }

    // report main, but ignore the stack frame set up for BEGIN blocks
    if (depth && line != &PL_compiling)
        trace.add_frame(CXt_NULL, NULL, line);
}
