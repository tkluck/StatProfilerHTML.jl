#include "runloop.h"
#include "ppport.h"

#include <time.h>
#include <pthread.h>

#include "tracecollector.h"
#include "tracefile.h"
#include "rand.h"

#include <string>

#ifndef OP_ENTRY_PROBE
# define OP_ENTRY_PROBE
#endif

using namespace devel::statprofiler;
using namespace std;

#define MY_CXT_KEY "Devel::StatProfiler::_guts" XS_VERSION

namespace {
    struct PerlMutex {
        PerlMutex() { MUTEX_INIT(&mutex); }
        ~PerlMutex() { MUTEX_DESTROY(&mutex); }

        operator perl_mutex *() { return &mutex; }

    private:
        perl_mutex mutex;
    };

    struct Cxt {
        string filename;
        bool is_template;
        bool enabled, using_trampoline, resuming;
        int runloop_level;
        runops_proc_t original_runloop;
        OP *switch_op;
        TraceFileWriter *trace;

        Cxt();
        Cxt(const Cxt &cxt);

        ~Cxt() {
            while (runloop_level)
                leave_runloop();
            delete trace;
        }

        TraceFileWriter *create_trace(pTHX);

        void enter_runloop();
        void leave_runloop();

        bool is_running() const;
        bool is_any_running() const;
    };

    struct CounterCxt {
        bool terminate;
        unsigned int start_delay;

        CounterCxt(unsigned int delay) :
            terminate(false), start_delay(delay) { }
    };
}

typedef struct Cxt my_cxt_t;

START_MY_CXT;

namespace {
    // global refcount for the counter thread
    int refcount = 0;
    // set to 'false' to terminate the counter thread
    bool *terminate = NULL;
    // hold this mutex before reading/writing refcount and terminate
    PerlMutex refcount_mutex;
    // global counter, written by increment_counter(), read by the runloops
    unsigned int counter = 0;
    // sampling interval, in microseconds
    unsigned int sampling_interval = 10000;
    // random start delay, to improve distribution
    unsigned int random_start = 0;
    // number of stack frames to collect
    unsigned int stack_collect_depth = 20;
    // Something largeish: 10MB
    size_t max_output_file_size = 10 * 1024*1024;
    bool seeded = false;
}

static bool
start_counter_thread(bool **terminate);


Cxt::Cxt() :
    filename("statprof.out"),
    is_template(true),
    enabled(true),
    using_trampoline(false),
    resuming(false),
    runloop_level(0),
    original_runloop(NULL),
    switch_op(NULL),
    trace(NULL)
{
}

Cxt::Cxt(const Cxt &cxt) :
    filename(cxt.filename),
    is_template(cxt.is_template),
    enabled(cxt.enabled),
    using_trampoline(false),
    resuming(false),
    runloop_level(0),
    original_runloop(NULL),
    switch_op(cxt.switch_op),
    trace(NULL)
{
}

TraceFileWriter *
Cxt::create_trace(pTHX)
{
    if (!trace) {
        trace = new TraceFileWriter(aTHX_ filename, is_template);
        trace->write_header(sampling_interval, stack_collect_depth);
    }

    return trace;
}

void
Cxt::enter_runloop()
{
    if (runloop_level == 0) {
        MUTEX_LOCK(refcount_mutex);

        if (++refcount == 1) {
            if (!start_counter_thread(&terminate)) {
                MUTEX_UNLOCK(refcount_mutex);
                croak("Unable to start counter thread");
            }
        }

        MUTEX_UNLOCK(refcount_mutex);
    }

    ++runloop_level;
}

void
Cxt::leave_runloop()
{
    if (runloop_level == 0)
        croak("Excess call to leave_runloop");

    if (runloop_level == 1) {
        MUTEX_LOCK(refcount_mutex);

        if (--refcount == 0) {
            *terminate = true;
            terminate = NULL;
        }

        MUTEX_UNLOCK(refcount_mutex);
    }

    --runloop_level;
}

bool
Cxt::is_running() const
{
    return runloop_level > 0 || (trace && trace->is_valid());
}

bool
Cxt::is_any_running() const
{
    if (is_running())
        return true;

    // no point in locking refcount_mutex here, if correctness is
    // needed, the mutex needs to be held around the whole section
    // using the result
    return refcount > 0;
}


static void
reopen_output_file(pTHX)
{
    dMY_CXT;
    MY_CXT.trace->close();
    MY_CXT.trace->open(MY_CXT.filename, MY_CXT.is_template);
    MY_CXT.trace->write_header(sampling_interval, stack_collect_depth);
    // XXX check if we need to write other metadata
}


static void *
increment_counter(void *arg)
{
    CounterCxt *cxt = static_cast<CounterCxt *>(arg);
    bool *terminate = &cxt->terminate;
    unsigned int delay = cxt->start_delay * 1000;

    while (!*terminate) {
        timespec sleep = {0, delay};
        while (clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep, &sleep) == EINTR)
            ;
        if (*terminate)
            break;
        delay = sampling_interval * 1000;
        ++counter;
    }
    delete cxt;

    return NULL;
}


static bool
start_counter_thread(bool **terminate)
{
    pthread_attr_t attr;
    pthread_t thread;
    bool ok = true;

    // init random seed
    if (!seeded) {
        seeded = true;
        random_start = rand_seed();
    }

    rand(&random_start);

    if (pthread_attr_init(&attr))
        return false;

    // discard low-order bits (they tend to be less random and we
    // don't need them anyway)
    CounterCxt *cxt = new CounterCxt((random_start >> 8) % sampling_interval);
    *terminate = &cxt->terminate;
    ok = ok && !pthread_attr_setstacksize(&attr, 65536);
    ok = ok && !pthread_create(&thread, &attr, &increment_counter, cxt);
    pthread_attr_destroy(&attr);

    if (!ok) {
        delete cxt;
        *terminate = NULL;
    }

    return ok;
}


// taken from pp_entersub in pp_hot.c, modified to return NULL rather
// than croak()ing or trying autoload
//
// since this runs after the call, some branches can likely be
// simplified (for example the SvGETMAGIC(), and the checks for
// SvOK()/strict refs)
static CV *
get_cv_from_sv(pTHX_ OP* op, SV *sv, GV **name)
{
    CV *cv = NULL;
    GV *gv = *name = NULL;

    switch (SvTYPE(sv)) {
        /* This is overwhelming the most common case:  */
    case SVt_PVGV:
      we_have_a_glob:
        if (!(cv = GvCVu((const GV *)sv))) {
            HV *stash;
            cv = sv_2cv(sv, &stash, &gv, 0);
        }
        if (!cv)
            return NULL;
        break;
    case SVt_PVLV:
        if(isGV_with_GP(sv)) goto we_have_a_glob;
        /*FALLTHROUGH*/
    default:
        if (sv == &PL_sv_yes)           /* unfound import, ignore */
            return NULL;
        /* SvGETMAGIC(sv) already called by pp_entersub/pp_goto */
        if (SvROK(sv)) {
            if (SvAMAGIC(sv)) {
                sv = amagic_deref_call(sv, to_cv_amg);
                /* Don't SPAGAIN here.  */
            }
        }
        else {
            const char *sym;
            STRLEN len;
            if (!SvOK(sv))
                return NULL;
            sym = SvPV_nomg_const(sv, len);
            if (op->op_private & HINT_STRICT_REFS)
                return NULL;
            cv = get_cvn_flags(sym, len, GV_ADD|SvUTF8(sv));
            break;
        }
        cv = MUTABLE_CV(SvRV(sv));
        if (SvTYPE(cv) == SVt_PVCV)
            break;
        /* FALL THROUGH */
    case SVt_PVHV:
    case SVt_PVAV:
        return NULL;
        /* This is the second most common case:  */
    case SVt_PVCV:
        cv = MUTABLE_CV(sv);
        break;
    }

    if (cv && !gv && CvGV(cv) && isGV_with_GP(CvGV(cv)))
        gv = CvGV(cv);

    *name = gv;
    return cv;
}

static int
runloop(pTHX)
{
    dVAR;
    dMY_CXT;
    OP *op = PL_op;
    OP *prev_op = NULL; // Could use PL_op for this, but PL_op might have indirection slowdown
    SV *called_sv = NULL;
    unsigned int pred_counter = counter;
    TraceFileWriter *trace = MY_CXT.create_trace(aTHX);

    if (!trace->is_valid())
        croak("Failed to open trace file");
    MY_CXT.enter_runloop();
    OP_ENTRY_PROBE(OP_NAME(op));
    while ((PL_op = op = op->op_ppaddr(aTHX))) {
        if (UNLIKELY( counter != pred_counter )) {
            trace->start_sample(counter - pred_counter, prev_op);
            if (prev_op &&
                (prev_op->op_type == OP_ENTERSUB ||
                 prev_op->op_type == OP_GOTO) &&
                (op == prev_op->op_next)) {
                // if the sub call is a normal Perl sub, op should be
                // pointing to CvSTART(), the fact is points to
                // op_next implies the call was to an XSUB
                GV *cv_name;
                CV *cv = get_cv_from_sv(aTHX_ prev_op, called_sv, &cv_name);

                if (cv && CvISXSUB(cv))
                    trace->add_frame(CXt_SUB, cv, cv_name, NULL);
#if 0 // DEBUG
                else {
                    const char *package = "__ANON__", *name = "(unknown)";

                    if (cv_name) {
                        package = HvNAME(GvSTASH(cv_name));
                        name = GvNAME(cv_name);
                    }

                    warn("Called sub %s::%s is not an XSUB", package, name);
                }
#endif
            }
            collect_trace(aTHX_ *trace, stack_collect_depth);
            trace->end_sample();
            if (trace->position() > max_output_file_size && MY_CXT.is_template) {
                // Start new output file
                reopen_output_file(aTHX);
            }
            pred_counter = counter;
        }
        // here we save the argument to entersub/goto so, if it ends
        // up calling an XSUB, we can retrieve sub call information
        // later (there is the possibility of the called sub modifying
        // called_sv through an alias, but is such a corner case that
        // is not worth the trouble)
        if (op->op_type == OP_ENTERSUB || op->op_type == OP_GOTO)
            called_sv = *PL_stack_sp;
        prev_op = op;
        OP_ENTRY_PROBE(OP_NAME(op));
    }
    MY_CXT.leave_runloop();
    PERL_ASYNC_CHECK();

    TAINT_NOT;
    return 0;
}


static int
trampoline(pTHX)
{
    dMY_CXT;
    int res;

    MY_CXT.using_trampoline = true;
    SAVEVPTR(PL_runops);

    do {
        MY_CXT.resuming = false;

        if (MY_CXT.enabled)
            PL_runops = runloop;
        else
            PL_runops = MY_CXT.original_runloop;

        res = CALLRUNOPS(aTHX);
        PL_op = MY_CXT.resuming ? MY_CXT.switch_op->op_next : NULL;
    } while (PL_op);

    return res;
}


static bool
switch_runloop(pTHX_ pMY_CXT_ bool enable)
{
    if (MY_CXT.runloop_level > 1) {
        warn("Trying to change profiling state from a nested runloop");
        return false;
    }

    if (enable == MY_CXT.enabled)
        return false;
    MY_CXT.enabled = enable;

    // the easy case, just let the trampoline handle the switch
    if (MY_CXT.using_trampoline)
        return true;

    if (!enable) {
        // this will exit the currently-running profiling runloop, and
        // continue at the line marked >>HERE<< below
        PL_runops = MY_CXT.original_runloop;
        return true;
    } else {
        PL_runops = runloop;
        PL_op = NORMAL;
        CALLRUNOPS(aTHX); // execution resumes >>HERE<<

        // if not resuming, the program ended for real, othwerwise restore
        // PL_op so the outer runloop keeps executing
        if (MY_CXT.resuming)
            PL_op = MY_CXT.switch_op;

        return false;
    }
}

static OP *
set_profiler_state(pTHX)
{
    dSP;
    dMY_CXT;
    int state = POPi;

    switch (state) {
    case 0: // disable
    case 1: // enable
        MY_CXT.resuming = switch_runloop(aTHX_ aMY_CXT_ state == 1);
        break;
    case 2: // restart
        if (MY_CXT.trace)
            reopen_output_file(aTHX);
        break;
    case 3: // stop
        if (MY_CXT.enabled) {
            MY_CXT.resuming = switch_runloop(aTHX_ aMY_CXT_ false);
            if (MY_CXT.trace)
                MY_CXT.trace->close();
        }
        break;
    }

    if (MY_CXT.resuming)
        RETURNOP((OP *) NULL);
    else
        RETURN;
}


static void
cleanup_runloop(pTHX_ void *ptr)
{
    dMY_CXT;
    MY_CXT.~Cxt();
}


void
devel::statprofiler::init_runloop(pTHX)
{
    MY_CXT_INIT;
    new(&MY_CXT) Cxt();

    Perl_call_atexit(aTHX_ cleanup_runloop, NULL);

    CV *enable_profiler = get_cv("Devel::StatProfiler::_set_profiler_state", 0);

    for (OP *o = CvSTART(enable_profiler); o; o = o->op_next) {
        if (o->op_type == OP_SRAND) {
            o->op_ppaddr = set_profiler_state;
            MY_CXT.switch_op = o;
            break;
        }
    }
}


void
devel::statprofiler::clone_runloop(pTHX)
{
    Cxt *original_cxt;

    {
        dMY_CXT;
        original_cxt = &MY_CXT;
    }

    MY_CXT_CLONE;
    new(&MY_CXT) Cxt(*original_cxt);
}


void
devel::statprofiler::install_runloop()
{
    dTHX;
    dMY_CXT;

    MY_CXT.original_runloop = PL_runops;
    if (MY_CXT.enabled)
        PL_runops = trampoline;
}


void
devel::statprofiler::set_enabled(bool enabled)
{
    dTHX;
    dMY_CXT;

    MY_CXT.enabled = enabled;
}

void
devel::statprofiler::set_output_file(const char *path, bool is_template)
{
    dTHX;
    dMY_CXT;

    if (MY_CXT.is_running()) {
        warn("Trying to change output file while profiling is in progress");
        return;
    }

    MY_CXT.filename = path;
    MY_CXT.is_template = is_template;
}

void
devel::statprofiler::set_sampling_interval(unsigned int interval)
{
    dTHX;
    dMY_CXT;

    if (MY_CXT.is_any_running()) {
        warn("Trying to change sampling interval while profiling is in progress");
        return;
    }

    if (interval == 0) {
        warn("Setting sampling interval to less than a microsecond not "
             "supported, defaulting to one microsecond");
        sampling_interval = 1;
    } else
        sampling_interval = interval;
}

void
devel::statprofiler::set_max_output_file_size(size_t max_size)
{
    // Changing this at run time should be safe.
    max_output_file_size = max_size;
}

void
devel::statprofiler::set_stack_collection_depth(unsigned int num_stack_frames)
{
    dTHX;
    dMY_CXT;

    if (MY_CXT.is_any_running()) {
        warn("Trying to change stack collection depth while profiling is in progress");
        return;
    }

    stack_collect_depth = num_stack_frames;
}

void
devel::statprofiler::write_custom_metadata(pTHX_ SV *key, SV *value)
{
    dMY_CXT;
    MY_CXT.trace->write_custom_metadata(key, value);
}
