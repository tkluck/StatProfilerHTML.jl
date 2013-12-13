#include "runloop.h"
#include "ppport.h"

#include <time.h>
#include <pthread.h>

#include "tracecollector.h"
#include "tracefile.h"

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

        TraceFileWriter *create_trace();

        void enter_runloop();
        void leave_runloop();
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
}

static bool
start_counter_thread(bool **terminate);


Cxt::Cxt() :
    filename("statprof.out"),
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
Cxt::create_trace()
{
    if (!trace)
        trace = new TraceFileWriter(filename);

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


static void *
increment_counter(void *arg)
{
    bool *terminate = static_cast<bool *>(arg);
    unsigned int delay = sampling_interval * 1000;

    while (!*terminate) {
        timespec sleep = {0, delay};
        while (clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep, &sleep) == EINTR)
            ;
        if (*terminate)
            break;
        ++counter;
    }
    delete terminate;

    return NULL;
}


static bool
start_counter_thread(bool **terminate)
{
    pthread_attr_t attr;
    pthread_t thread;
    bool ok = true;

    if (pthread_attr_init(&attr))
        return false;

    *terminate = new bool(false);
    ok = ok && !pthread_attr_setstacksize(&attr, 65536);
    ok = ok && !pthread_create(&thread, &attr, &increment_counter, *terminate);
    pthread_attr_destroy(&attr);

    if (!ok) {
        delete *terminate;
        *terminate = NULL;
    }

    return ok;
}


static int
runloop(pTHX)
{
    dVAR;
    dMY_CXT;
    OP *op = PL_op;
    OP *prev_op = NULL; // Could use PL_op for this, but PL_op might have indirection slowdown
    unsigned int pred_counter = counter;
    TraceFileWriter *trace = MY_CXT.create_trace();

    if (!trace->is_valid())
        croak("Failed to open trace file");
    MY_CXT.enter_runloop();
    OP_ENTRY_PROBE(OP_NAME(op));
    while ((PL_op = op = op->op_ppaddr(aTHX))) {
        if (UNLIKELY( counter != pred_counter )) {
            trace->start_sample(counter - pred_counter);
            collect_trace(aTHX_ *trace, 20);
            trace->add_topmost_op(aTHX_ prev_op);
            trace->end_sample();
            pred_counter = counter;
        }
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
        if (MY_CXT.trace) {
            MY_CXT.trace->close();
            MY_CXT.trace->open(MY_CXT.filename);
            // XXX check, write metadata
        }
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
devel::statprofiler::set_output_file(const char *path)
{
    dTHX;
    dMY_CXT;

    MY_CXT.filename = path;
}

void
devel::statprofiler::set_sampling_interval(unsigned int interval)
{
    sampling_interval = interval;
}
