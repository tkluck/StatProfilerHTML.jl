#include "runloop.h"
#include "ppport.h"

#include <time.h>
#include <pthread.h>

#include "tracecollector.h"
#include "tracefile.h"

#include <string>

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
        bool enabled;
        int runloop_level;
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
    runloop_level(0),
    trace(NULL)
{
}

Cxt::Cxt(const Cxt &cxt) :
    filename(cxt.filename),
    enabled(cxt.enabled),
    runloop_level(0),
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
    unsigned int pred_counter = counter;
    TraceFileWriter *trace = MY_CXT.create_trace();

    if (!trace->is_valid())
        croak("Failed to open trace file");
    MY_CXT.enter_runloop();
    OP_ENTRY_PROBE(OP_NAME(op));
    while ((PL_op = op = op->op_ppaddr(aTHX))) {
        if (counter != pred_counter) {
            trace->start_sample(counter - pred_counter);
            collect_trace(aTHX_ *trace, 20);
            trace->end_sample();
            pred_counter = counter;
        }
        OP_ENTRY_PROBE(OP_NAME(op));
    }
    MY_CXT.leave_runloop();
    PERL_ASYNC_CHECK();

    TAINT_NOT;
    return 0;
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

    if (MY_CXT.enabled)
        PL_runops = runloop;
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
