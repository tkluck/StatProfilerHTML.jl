#include "rand.h"

#include <cstddef>
#include <sys/time.h>

using namespace devel::statprofiler;

unsigned int
devel::statprofiler::rand_seed()
{
    timeval now;

    gettimeofday(&now, NULL);

    return now.tv_sec * 1000 + now.tv_usec / 1000;
}

void
devel::statprofiler::rand(unsigned int *seed)
{
    // ANSI C linear congruential PRNG
    *seed = (*seed * 1103515245 + 12345) & 0x7fffffffu;
}
