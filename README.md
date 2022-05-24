# StatProfilerHTML

| **Build Status**         | **Test coverage**                                 |
|:------------------------:|:-------------------------------------------------:|
| [![][c-i-img]][c-i-url]  | [![Coverage Status][codecov-img]][codecov-url]    |
|                          |                                                   |


This module formats the output from Julia's Profile module into an html
rendering of the source function lines and functions, allowing for interactive
exploration of any bottlenecks that may exist in your code.

There's two ways of using this:

 - call `statprofilehtml()` after running the julia profiler in the normal way; or
 - use the `@profilehtml` macro.


Have a look [at this example output](http://www.infty.nl/StatProfilerHTML.jl/example-output/), which
is the result of profiling

    using StatProfilerHTML
    using TypedPolynomials
    @polyvar x y z
    @profilehtml (x + y + z)^120;


[c-i-img]: https://github.com/tkluck/StatProfilerHTML.jl/workflows/CI/badge.svg
[c-i-url]: https://github.com/tkluck/StatProfilerHTML.jl/actions?query=workflow%3ACI

[codecov-img]: https://codecov.io/gh/tkluck/StatProfilerHTML.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/tkluck/StatProfilerHTML.jl
