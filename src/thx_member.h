#ifndef _DEVEL_STATPROFILER_THX_MEMBER
#define _DEVEL_STATPROFILER_THX_MEMBER

// Defines macros for use in classes that keep a Perl threading
// context around.
//
// Example:
// class Foo {
// public:
//   Foo(pTHX) {
//    SET_THX_MEMBER
//   }
//   void bar() {
//     // use aTHX here implicitly or explicitly
//   }
// private:
//   DECL_THX_MEMBER
// }

#include <EXTERN.h>
#include <perl.h>

#ifdef MULTIPLICITY
#   define DECL_THX_MEMBER tTHX my_perl;
#   define SET_THX_MEMBER this->my_perl = aTHX;
#else
#   define DECL_THX_MEMBER
#   define SET_THX_MEMBER
#endif

#endif
