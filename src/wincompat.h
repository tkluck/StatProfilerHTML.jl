#ifndef _DEVEL_STATPROFILER_WINCOMPAT
#define _DEVEL_STATPROFILER_WINCOMPAT

// undo hateful PerlIO redefinitions
#undef open
#undef close

typedef unsigned char uint8_t;
typedef unsigned short int uint16_t;
typedef unsigned int uint32_t;
#if defined(_MSC_VER)
typedef unsigned __int64 uint64_t;
#else
typedef unsigned long long uint64_t;
#endif

#endif
