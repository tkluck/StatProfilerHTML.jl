#include "tracecollector.h"


static void
collect_caller_info(pTHX_ int depth, const PERL_CONTEXT *caller, const PERL_CONTEXT *sub)
{
    COP *callsite = caller->blk_oldcop;
    HV *callpackage = CopSTASH(callsite);
    const char *name, *package = "__ANON__";

    // from Perl_pp_caller
    if (CxTYPE(sub) == CXt_SUB || CxTYPE(sub) == CXt_FORMAT) {
	GV * const cvgv = CvGV(sub->blk_sub.cv);
	if (cvgv && isGV(cvgv)) {
            GV *egv = GvEGVx(cvgv) ? GvEGVx(cvgv) : cvgv;
            HV *stash = GvSTASH(egv);

            if (stash)
                package = HvNAME(stash);
            name = GvNAME(egv);
	}
	else {
            name = "(unknown)";
	}
    } else {
        package = "(eval)";
        name = "(eval)";
    }
#if 0
    // XXX
    printf("%s::%s at %s %s:%d ",
           package, name,
           HvNAME_get(callpackage), OutCopFILE(callsite), CopLINE(callsite));
#endif
}


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
            if (cx->cx_type & CXp_SUB_RE_FAKE)
                continue;
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
devel::statprofiler::collect_trace(pTHX_ int depth)
{
    I32 cxix = S_dopoptosub_at(aTHX_ cxstack, cxstack_ix);
    const PERL_CONTEXT *ccstack = cxstack;
    const PERL_SI *top_si = PL_curstackinfo;
    CV *db_sub = PL_DBsub ? GvCV(PL_DBsub) : NULL;

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
            if (db_sub) {
                // when there is a &DB::sub, we need its call site to get
                // the correct file/line information
                I32 dbcxix = S_dopoptosub_at(aTHX_ ccstack, cxix - 1);

                if (dbcxix >= 0 && ccstack[dbcxix].blk_sub.cv == db_sub) {
                    collect_caller_info(aTHX_ depth, &ccstack[dbcxix], &ccstack[cxix]);
                    cxix = dbcxix;
                }
                else
                    collect_caller_info(aTHX_ depth, &ccstack[cxix], &ccstack[cxix]);
            } else {
                collect_caller_info(aTHX_ depth, &ccstack[cxix], &ccstack[cxix]);
            }
            if (!--depth)
                break;
        }
        cxix = S_dopoptosub_at(aTHX_ ccstack, cxix - 1);
    }
#if 0
    printf("\n"); // XXX
#endif
}
