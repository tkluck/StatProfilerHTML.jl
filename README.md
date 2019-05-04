# StatProfilerHTML

| **PackageEvaluator**       | **Build Status**                                                | **Test coverage**                                       |
|:--------------------------:|:---------------------------------------------------------------:|:-------------------------------------------------------:|
|[![][pkg-0.6-img]][pkg-url] | [![][travis-img]][travis-url] [![][appveyor-img]][appveyor-url] | [![Coverage Status][coveralls-img]][coveralls-url]      |
|[![][pkg-0.7-img]][pkg-url] |                                                                 |                                                         |


This module formats the output from Julia's Profile module into an html
rendering of the source function lines and functions, allowing for interactive
exploration of any bottlenecks that may exist in your code.

There's two ways of using this:

 - call `statprofilehtml()` after running the julia profiler in the normal way; or
 - use the `@profilehtml` macro.


Have a look [at this example output](http://www.infty.nl/StatProfilerHTML.jl/example-output/), which
is the result of profiling

    using StatProfilerHTML
    using MultivariatePolynomials
    @polyvar x y z
    @profilehtml (x + y + z)^120;


This module contains a fork of the rendering part of Mattia Barbon and Steffen
Müller's excellent
[Devel::StatProfiler](https://github.com/mbarbon/devel-statprofiler), which is
a statistical profiler for Perl. It depends on Text::MicroTemplate, which for
convenience, we ship as part of this bundle.


## Line number bug
On the latest version of Julia, this package is severly affected by the
issue with line numbers [as tracked in this bug report](https://github.com/JuliaLang/julia/issues/28618). Julia developers will hopefully fix this soon!

[travis-img]: https://travis-ci.org/tkluck/StatProfilerHTML.jl.svg?branch=master
[travis-url]: https://travis-ci.org/tkluck/StatProfilerHTML.jl

[appveyor-img]: https://ci.appveyor.com/api/projects/status/mwnbnfp1gjm8ux3d?svg=true
[appveyor-url]: https://ci.appveyor.com/project/tkluck/statprofilerhtml-jl

[pkg-0.6-img]: http://pkg.julialang.org/badges/StatProfilerHTML_0.6.svg
[pkg-0.7-img]: http://pkg.julialang.org/badges/StatProfilerHTML_0.7.svg
[pkg-url]: http://pkg.julialang.org/?pkg=StatProfilerHTML

[coveralls-img]: https://coveralls.io/repos/github/tkluck/StatProfilerHTML.jl/badge.svg?branch=master
[coveralls-url]: https://coveralls.io/github/tkluck/StatProfilerHTML.jl?branch=master
