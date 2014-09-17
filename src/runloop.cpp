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
    enum SourceCodeKind {
        NONE             = 0,
        TRACED_EVALS     = 1,
        ALL_EVALS        = 2,
        ALL_EVALS_ALWAYS = 3,
    };

    struct Mutex {
        Mutex() {
            reinit();
        }

        ~Mutex() {
            int rc = pthread_mutex_destroy(&mutex);

            if (rc)
                Perl_croak_nocontext("Devel::StatProfiler: error %d destroying mutex", rc);
        }

        void lock() {
            int rc = pthread_mutex_lock(&mutex);

            if (rc)
                Perl_croak_nocontext("Devel::StatProfiler: error %d locking mutex", rc);
        }

        void unlock() {
            int rc = pthread_mutex_unlock(&mutex);

            if (rc)
                Perl_croak_nocontext("Devel::StatProfiler: error %d unlocking mutex", rc);
        }

        void reinit() {
            memset(&mutex, 0, sizeof(mutex)); // just in case

            int rc = pthread_mutex_init(&mutex, NULL);

            if (rc)
                Perl_croak_nocontext("Devel::StatProfiler: error %d initializing mutex", rc);
        }
    private:
        pthread_mutex_t mutex;
    };

    struct Cxt {
        string filename;
        bool is_template;
        bool enabled, using_trampoline, resuming, outer_runloop;
        runops_proc_t original_runloop;
        OP *switch_op;
        unsigned int rand_id;
        uint32_t id[ID_SIZE], parent_id[ID_SIZE];
        unsigned int ordinal, parent_ordinal;
        pid_t pid, tid;
        TraceFileWriter *trace;

        Cxt();
        Cxt(const Cxt &cxt);
        ~Cxt();

        TraceFileWriter *create_trace(pTHX);

        void enter_runloop();
        void leave_runloop();

        bool is_running() const;
        bool is_any_running() const;

        void new_id();
        void pid_changed();
    };

    struct CounterCxt {
        bool terminate;
        unsigned int start_delay;

        CounterCxt(unsigned int delay) :
            terminate(false), start_delay(delay) { }
    };
}

typedef struct Cxt my_cxt_t;

// real and test versions
static void *
increment_counter(void *arg);
static void *
test_increment_counter(void *arg);

START_MY_CXT;

namespace {
    // call pthread_atfork once
    pthread_once_t call_atfork = PTHREAD_ONCE_INIT;
    // global refcount for the counter thread
    int refcount = 0;
    // set to 'false' to terminate the counter thread
    bool *terminate_counter_thread = NULL;
    // hold this mutex before reading/writing refcount and
    // terminate_counter_thread
    Mutex refcount_mutex;
    // global thread identifier
    int thread_id = 1;
#ifdef USE_ITHREADS
    // hold this mutex before reading/writing tid
    Mutex tid_mutex;
#endif
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
    // which source code needs saving, see StatProfiler.pm
    SourceCodeKind source_code_kind = NONE;
    bool seeded = false;
    // hooks for saving eval text
    BHK scope_hooks;

    // used for testing, but so small we always allocate them
    Mutex test_counter_increment_mutex;
    unsigned int test_counter_increment = 0;
    void * (* increment_counter_function)(void *arg) = &increment_counter;
}

static bool
start_counter_thread(bool **terminate);


static int
new_thread_id()
{
#ifdef USE_ITHREADS
    tid_mutex.lock();
    int id = ++thread_id;
    tid_mutex.unlock();

    return id;
#else
    return ++thread_id;
#endif
}


Cxt::Cxt() :
    filename("statprof.out"),
    is_template(true),
    enabled(true),
    using_trampoline(false),
    resuming(false),
    outer_runloop(false),
    original_runloop(NULL),
    switch_op(NULL),
    rand_id(rand_seed()),
    ordinal(0),
    parent_ordinal(0),
    pid(getpid()),
    tid(new_thread_id()),
    trace(NULL)
{
    new_id();
}

Cxt::Cxt(const Cxt &cxt) :
    filename(cxt.filename),
    is_template(cxt.is_template),
    enabled(cxt.enabled),
    using_trampoline(false),
    resuming(false),
    outer_runloop(false),
    original_runloop(NULL),
    switch_op(cxt.switch_op),
    rand_id(cxt.rand_id),
    ordinal(0),
    parent_ordinal(cxt.ordinal),
    pid(cxt.pid),
    tid(new_thread_id()),
    trace(NULL)
{
    new_id();
    memcpy(parent_id, cxt.id, sizeof(id));
}

Cxt::~Cxt() {
    dTHX;

    if (outer_runloop)
        Perl_croak(aTHX_ "Devel::StatProfiler: deleting context for a running runloop");
    PL_runops = original_runloop;
    if (trace && trace->is_valid())
        trace->close(TraceFileWriter::write_end_tag);
    delete trace;
}

TraceFileWriter *
Cxt::create_trace(pTHX)
{
    if (!trace)
        trace = new TraceFileWriter(aTHX);

    if (!trace->is_valid()) {
        ++ordinal;

        trace->open(filename, is_template, id, ordinal);
        trace->write_header(sampling_interval, stack_collect_depth,
                            id, ordinal, parent_id, parent_ordinal);
    }

    return trace;
}

void
Cxt::enter_runloop()
{
    if (outer_runloop)
        croak("Excess call to enter_runloop");

    refcount_mutex.lock();

    if (++refcount == 1) {
        if (!start_counter_thread(&terminate_counter_thread)) {
            refcount_mutex.unlock();
            croak("Error %d while starting counter thread", errno);
        }
    }

    outer_runloop = true;
    refcount_mutex.unlock();
}

void
Cxt::leave_runloop()
{
    if (!outer_runloop)
        croak("Excess call to leave_runloop");

    refcount_mutex.lock();
    outer_runloop = false;

    if (--refcount == 0) {
        *terminate_counter_thread = true;
        terminate_counter_thread = NULL;
    }

    refcount_mutex.unlock();
}

bool
Cxt::is_running() const
{
    return outer_runloop || (trace && trace->is_valid());
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

void
Cxt::new_id()
{
    id[0] = pid;
    id[1] = tid;
    id[2] = time(NULL);

    for (int i = 0; i < 3; ++i) {
        rand(&rand_id);
        id[i + 3] = rand_id;
    }

    ordinal = 0;
}

void
Cxt::pid_changed()
{
    memcpy(parent_id, id, sizeof(parent_id));
    parent_ordinal = ordinal;

    pid = getpid();
    tid = new_thread_id();

    new_id();
}

static void
reopen_output_file(pTHX_ pMY_CXT)
{
    MY_CXT.trace->close();

    ++MY_CXT.ordinal;

    MY_CXT.trace->open(MY_CXT.filename, MY_CXT.is_template,
                       MY_CXT.id, MY_CXT.ordinal);
    MY_CXT.trace->write_header(sampling_interval, stack_collect_depth,
                               MY_CXT.id, MY_CXT.ordinal, MY_CXT.parent_id, MY_CXT.parent_ordinal);
    // XXX check if we need to write other metadata
}


static void *
increment_counter(void *arg)
{
    CounterCxt *cxt = static_cast<CounterCxt *>(arg);
    bool *terminate = &cxt->terminate;
    unsigned int delay_sec = cxt->start_delay / 1000000,
                 delay_nsec = cxt->start_delay % 1000000 * 1000;

    while (!*terminate) {
        timespec sleep = {delay_sec, delay_nsec};
        while (clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep, &sleep) == EINTR)
            ;
        if (*terminate)
            break;
        delay_sec = sampling_interval / 1000000;
        delay_nsec = sampling_interval % 1000000 * 1000;
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
    ok = ok && !pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    ok = ok && !pthread_create(&thread, &attr, increment_counter_function, cxt);

    int old_errno = errno;
    pthread_attr_destroy(&attr);

    if (!ok) {
        delete cxt;
        *terminate = NULL;
        errno = old_errno;
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

static void
collect_sample(pTHX_ pMY_CXT_ TraceFileWriter *trace, unsigned int pred_counter, OP *op, OP *prev_op, SV *called_sv)
{
    if (trace->position() > max_output_file_size && MY_CXT.is_template) {
        // Start new output file
        reopen_output_file(aTHX_ aMY_CXT);
    }
    trace->start_sample(counter - pred_counter, prev_op);
    if (prev_op &&
        (prev_op->op_type == OP_ENTERSUB ||
         prev_op->op_type == OP_GOTO) &&
        (op == prev_op->op_next) && called_sv) {
        // if the sub call is a normal Perl sub, op should be
        // pointing to CvSTART(), the fact is points to
        // op_next implies the call was to an XSUB
        GV *cv_name;
        CV *cv = get_cv_from_sv(aTHX_ prev_op, called_sv, &cv_name);

        if (cv && CvISXSUB(cv))
            trace->add_frame(FRAME_XSUB, cv, cv_name, NULL);
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
    collect_trace(aTHX_ *trace, stack_collect_depth,
                  source_code_kind == TRACED_EVALS);
    trace->end_sample();
}

static void
enter_eval_hook(pTHX_ OP *o)
{
    if (o->op_type != OP_ENTEREVAL)
        return;

    dMY_CXT;

    if (MY_CXT.enabled || source_code_kind == ALL_EVALS_ALWAYS) {
        TraceFileWriter *trace = MY_CXT.create_trace(aTHX);

        trace->add_eval_source(cxstack[cxstack_ix].blk_eval.cur_text, NULL, PL_evalseq);
    }
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

    OP_ENTRY_PROBE(OP_NAME(op));
    while ((PL_op = op = op->op_ppaddr(aTHX))) {
        if (UNLIKELY( counter != pred_counter )) {
            collect_sample(aTHX_ aMY_CXT_ trace, pred_counter, op, prev_op, called_sv);
            pred_counter = counter;
        }
        // here we save the argument to entersub/goto so, if it ends
        // up calling an XSUB, we can retrieve sub call information
        // later (there is the possibility of the called sub modifying
        // called_sv through an alias, but is such a corner case that
        // is not worth the trouble)
        called_sv = *PL_stack_sp;
        prev_op = op;
        OP_ENTRY_PROBE(OP_NAME(op));
    }
    PERL_ASYNC_CHECK();

    TAINT_NOT;
    return 0;
}


static int
trampoline(pTHX)
{
    dMY_CXT;
    dJMPENV;
    int res, exc;

    MY_CXT.using_trampoline = true;
    MY_CXT.enter_runloop();

    JMPENV_PUSH(exc);
    switch (exc) {
    case 0:
    redo_body:
        do {
            MY_CXT.resuming = false;

            if (MY_CXT.enabled)
                PL_runops = runloop;
            else
                PL_runops = MY_CXT.original_runloop;

            res = CALLRUNOPS(aTHX);
            PL_op = MY_CXT.resuming ? MY_CXT.switch_op->op_next : NULL;
        } while (PL_op);

        break;
    case 3:
	/* die caught by an inner eval - continue inner loop */
	if (PL_restartop && PL_restartjmpenv == PL_top_env) {
	    PL_restartjmpenv = NULL;
	    PL_op = PL_restartop;
	    PL_restartop = 0;
	    goto redo_body;
	}
	/* FALL THROUGH */
    default:
	JMPENV_POP;
        PL_runops = trampoline;
        MY_CXT.leave_runloop();

	JMPENV_JUMP(exc);
	/* NOTREACHED */
    }

    JMPENV_POP;
    PL_runops = trampoline;
    MY_CXT.leave_runloop();

    return res;
}


static bool
switch_runloop(pTHX_ pMY_CXT_ bool enable)
{
    if (enable == MY_CXT.enabled)
        return false;
    MY_CXT.enabled = enable;

    // the easy case, just let the trampoline handle the switch
    if (MY_CXT.using_trampoline)
        return true;

    if (!enable) {
        // this will exit the currently-running profiling runloop, and
        // continue at the line marked >>HERE<< below
        return true;
    } else {
        dJMPENV;
        int exc;

        MY_CXT.enter_runloop();
        PL_runops = runloop;
        PL_op = NORMAL;

        JMPENV_PUSH(exc);
        switch (exc) {
        case 0:
        redo_body:
            CALLRUNOPS(aTHX); // execution resumes >>HERE<<
            break;

        case 3:
            /* die caught by an inner eval - continue inner loop */
            if (PL_restartop && PL_restartjmpenv == PL_top_env) {
                PL_restartjmpenv = NULL;
                PL_op = PL_restartop;
                PL_restartop = 0;
                goto redo_body;
            }
            /* FALL THROUGH */
        default:
            JMPENV_POP;
            PL_runops = MY_CXT.original_runloop;
            MY_CXT.leave_runloop();

            JMPENV_JUMP(exc);
            /* NOTREACHED */
        }

        JMPENV_POP;
        // for embedded interpreters where the code is called via call_sv,
        // preserve the tracing status between call_sv invocations
        if (MY_CXT.enabled)
            PL_runops = trampoline;
        else
            PL_runops = MY_CXT.original_runloop;
        MY_CXT.leave_runloop();

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
            reopen_output_file(aTHX_ aMY_CXT);
        break;
    case 3: // stop
        if (MY_CXT.enabled)
            MY_CXT.resuming = switch_runloop(aTHX_ aMY_CXT_ false);
        if (MY_CXT.trace)
            MY_CXT.trace->close(TraceFileWriter::write_end_tag);
        break;
    }

    // PL_op can be NULL if we aren't using the trampoline and the
    // program ran to completion with tracing still on
    if (MY_CXT.resuming || !PL_op)
        RETURNOP((OP *) NULL);
    else
        RETURN;
}


static void
cleanup_runloop(pTHX_ void *ptr)
{
    dMY_CXT;

    if (MY_CXT.trace)
        MY_CXT.trace->close(TraceFileWriter::write_end_tag);

    // declared static and destroyed during global destruction
#ifdef PERL_IMPLICIT_CONTEXT
    MY_CXT.~Cxt();
#endif
}


static void
prepare_fork()
{
    dTHX;
    dMY_CXT;

    if (MY_CXT.trace)
        MY_CXT.trace->flush();
    refcount_mutex.lock();
}


static void
parent_after_fork()
{
    dTHX;
    dMY_CXT;

    refcount_mutex.unlock();
    // ensures that any eval text the child depends on is in an
    // already closed file, ready for processing
    if (MY_CXT.trace && MY_CXT.trace->is_valid()) {
        MY_CXT.trace->close();
        if (MY_CXT.outer_runloop)
            reopen_output_file(aTHX_ aMY_CXT);
    }
}


static void
child_after_fork()
{
    dTHX;
    dMY_CXT;

    bool running = MY_CXT.is_running();

    if (MY_CXT.trace)
        MY_CXT.trace->shut();

    refcount_mutex.reinit();
    refcount = running ? 1 : 0;

    if (running && !start_counter_thread(&terminate_counter_thread))
        croak("Error %d while restarting counter thread", errno);

    MY_CXT.pid_changed();
    MY_CXT.ordinal = 0;
    if (running && MY_CXT.trace)
        reopen_output_file(aTHX_ aMY_CXT);
}


static void
init_atfork()
{
    pthread_atfork(prepare_fork, parent_after_fork, child_after_fork);
}


void
devel::statprofiler::init_runloop(pTHX)
{
    MY_CXT_INIT;
    new(&MY_CXT) Cxt();

    Perl_call_atexit(aTHX_ cleanup_runloop, NULL);

    pthread_once(&call_atfork, init_atfork);

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

    // ensures that any eval text the child depends on is in an
    // already closed file, ready for processing
    if (original_cxt->trace && original_cxt->trace->is_valid())
        reopen_output_file(aTHX_
#ifdef PERL_IMPLICIT_CONTEXT
                           original_cxt
#endif
        );
}


void
devel::statprofiler::install_runloop()
{
    dTHX;
    dMY_CXT;

    MY_CXT.original_runloop = PL_runops;
    if (MY_CXT.enabled) // for the -nostart case
        PL_runops = trampoline;

    BhkENTRY_set(&scope_hooks, bhk_eval, enter_eval_hook);
    Perl_blockhook_register(aTHX_ &scope_hooks);
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
devel::statprofiler::set_save_source(unsigned int save_source)
{
    dTHX;
    dMY_CXT;

    if (MY_CXT.is_any_running()) {
        warn("Trying to change source saving setting while profiling is in progress");
        return;
    }

    source_code_kind = (SourceCodeKind) save_source;
}

void
devel::statprofiler::write_custom_metadata(pTHX_ SV *key, SV *value)
{
    dMY_CXT;

    if (MY_CXT.trace)
        MY_CXT.trace->write_custom_metadata(key, value);
}

void
devel::statprofiler::start_section(pTHX_ SV *section_name)
{
    dMY_CXT;

    if (MY_CXT.trace)
        MY_CXT.trace->start_section(section_name);
}

void
devel::statprofiler::end_section(pTHX_ SV *section_name)
{
    dMY_CXT;

    if (MY_CXT.trace)
        MY_CXT.trace->end_section(section_name);
}

int
devel::statprofiler::get_precision()
{
    if (increment_counter_function = &test_increment_counter)
        return 1;

    timespec res;

    if (clock_getres(CLOCK_MONOTONIC, &res))
        return -1;

    return res.tv_sec * 1000000 + res.tv_nsec / 1000;
}

bool
devel::statprofiler::is_running()
{
    dTHX;
    dMY_CXT;

    return MY_CXT.is_running();
}

// disgusting test hackery
//
// overrides Time::HiRes::{usleep,sleep,time}, OP_FTDIR, OP_UNSTACK,
// OP_NEXTSTATE and the counter thread to simulate a controlled
// version of time, to make the tests less sensitive to system load
//
// enable with Devel::StatProfiler::Test::test_enable()

// fake opcode implementation for ftdir/unstack/nextstate
static Perl_ppaddr_t orig_ftdir, orig_unstack, orig_nextstate;

static OP *
test_ftdir(pTHX)
{
    test_force_sample(79);

    return orig_ftdir(aTHX);
}

static OP *
test_unstack(pTHX)
{
    test_force_sample(23);

    return orig_unstack(aTHX);
}

static OP *
test_nextstate(pTHX)
{
    test_force_sample(13);

    return orig_nextstate(aTHX);
}

// overrides the XS implementation for Time::HiRes functions using the
// one provided below
static void
fake_hires_function(const char *name)
{
    dTHX;

    char src[100], dst[100];

    strcpy(src, "Devel::StatProfiler::Test::test_hires_");
    strcat(src, name);

    strcpy(dst, "Time::HiRes::");
    strcat(dst, name);

    CV *src_cv = get_cv(src, 0);
    if (!src_cv)
        croak("Unable to get source XSUB for '%s'", src);

    CV *dst_cv = get_cv(dst, 0);
    if (!dst_cv)
        croak("Unable to get source XSUB for '%s'", dst);

    CvXSUB(dst_cv) = CvXSUB(src_cv);
}

void
devel::statprofiler::test_enable()
{
    increment_counter_function = &test_increment_counter;

    fake_hires_function("usleep");
    fake_hires_function("sleep");
    fake_hires_function("time");

    orig_ftdir = PL_ppaddr[OP_FTDIR];
    orig_unstack = PL_ppaddr[OP_UNSTACK];
    orig_nextstate = PL_ppaddr[OP_NEXTSTATE];

    PL_ppaddr[OP_FTDIR] = test_ftdir;
    PL_ppaddr[OP_UNSTACK] = test_unstack;
    PL_ppaddr[OP_NEXTSTATE] = test_nextstate;
}

double
devel::statprofiler::test_hires_usleep(unsigned int usec)
{
    test_force_sample(usec);

    return usec;
}

double
devel::statprofiler::test_hires_sleep(double sleep)
{
    test_hires_usleep(sleep * 1000000);

    return sleep;
}

double
devel::statprofiler::test_hires_time()
{
    return 1234567890 + counter * (sampling_interval / 1000000.0);
}

void
devel::statprofiler::test_force_sample(unsigned int increment)
{
    dTHX;
    dMY_CXT;

    static unsigned int seed = rand_seed();

    // we could just increment the counter by increment and be done
    // with it, but this way the test is more realistic (the counter
    // is incremented by a separate thread, and we test the thread is
    // running)
    rand(&seed);

    test_counter_increment_mutex.lock();
    test_counter_increment += increment + (seed % increment) / 5;
    if (test_counter_increment < sampling_interval) {
        test_counter_increment_mutex.unlock();
        return;
    }
    test_counter_increment_mutex.unlock();

    // ugly and inefficient, but good enough for testing
    for (;MY_CXT.outer_runloop;) {
        test_counter_increment_mutex.lock();
        if (test_counter_increment < sampling_interval) {
            test_counter_increment_mutex.unlock();
            break;
        }
        test_counter_increment_mutex.unlock();

        timespec sleep = {0, 100000};
        while (clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep, &sleep) == EINTR)
            ;
    }

    if (!MY_CXT.outer_runloop) {
        test_counter_increment_mutex.lock();
        counter += test_counter_increment / sampling_interval;
        test_counter_increment %= sampling_interval;
        test_counter_increment_mutex.unlock();
    }
}

static void *
test_increment_counter(void *arg)
{
    CounterCxt *cxt = static_cast<CounterCxt *>(arg);
    bool *terminate = &cxt->terminate;

    while (!*terminate) {
        timespec sleep = {0, 100000};
        while (clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep, &sleep) == EINTR)
            ;

        test_counter_increment_mutex.lock();
        if (test_counter_increment >= sampling_interval) {
            counter += test_counter_increment / sampling_interval;
            test_counter_increment %= sampling_interval;
        }
        test_counter_increment_mutex.unlock();

        if (*terminate)
            break;
    }
    delete cxt;

    return NULL;
}
