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
    struct Cxt {
        string filename;
        TraceFileWriter *trace;

        Cxt();

        ~Cxt() {
            delete trace;
        }

        TraceFileWriter *create_trace();
    };
}

typedef struct Cxt my_cxt_t;

START_MY_CXT;

Cxt::Cxt() :
    filename("statprof.out"),
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

static unsigned int counter = 0;


static void *
increment_counter(void *arg)
{
    bool *terminate = static_cast<bool *>(arg);

    while (!*terminate) {
        timespec sleep = {0, 1000000}; // 1 msec
        while (clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep, &sleep) == EINTR)
            ;
        if (*terminate)
            break;
        ++counter;
    }
    delete terminate;

    return NULL;
}


bool
start_counter_thread(bool *terminate)
{
    pthread_attr_t attr;
    pthread_t thread;
    bool ok = true;

    if (pthread_attr_init(&attr))
        return false;

    *terminate = false;
    ok = ok && !pthread_attr_setstacksize(&attr, 65536);
    ok = ok && !pthread_create(&thread, &attr, &increment_counter, terminate);
    pthread_attr_destroy(&attr);

    return ok;
}


int
devel::statprofiler::runloop(pTHX)
{
    dVAR;
    dMY_CXT;
    OP *op = PL_op;
    unsigned int pred_counter = counter;
    bool *terminate = new bool;
    TraceFileWriter *trace = MY_CXT.create_trace();

    if (!trace->is_valid())
        croak("Failed to open trace file");
    if (!start_counter_thread(terminate))
        croak("Failed to start counter thread");
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
    *terminate = true;
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
