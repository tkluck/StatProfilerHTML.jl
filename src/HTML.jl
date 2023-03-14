module HTML


import SHA: sha1
import Dates: format, RFC1123Format
import StableRNGs: StableRNG

import HAML: includehaml, @include, @surround, @cdatafile, @output

import ..Reports: Report, FunctionPoint, TracePoint

# needs to be smaller than 250 on MacOS, and anecdotally, the length of a full
# path needs to be at most 260 on Windows. This should give some spare room
# in either case.
const MAX_OUTPUT_FILE_NAME_LENGTH = 150

templatefile(name...) = joinpath(@__DIR__, "..", "haml", name...)

includehaml(@__MODULE__,
    :render_sourcefile => templatefile("sourcefile.hamljl"),
    :render_index      => templatefile("index.hamljl"),
    :render_files      => templatefile("files.hamljl"),
    :render_methods    => templatefile("methods.hamljl"),
    :render_flamegraph => templatefile("flamegraph.hamljl"),
    :render_flamegraphitem => templatefile("flamegraphitem.hamljl"),
)

outputfilename(::Report, ::Nothing) = ""
outputfilename(r::Report, sourcefile::Symbol) = begin
    s = string(sourcefile)
    b = basename(s)
    r = relpath(s, r.startpath)
    x = bytes2hex(sha1(r))
    b = first(b, MAX_OUTPUT_FILE_NAME_LENGTH - length(x) - length("-.html"))
    return "$b-$x.html"
end

href(r::Report, pt::FunctionPoint) = begin
    fn = outputfilename(r, pt.point.file)
    anchor = "L$(pt.point.line)"
    return "$fn#$anchor"
end

href(r::Report, pt::TracePoint) = begin
    fn = outputfilename(r, pt.point.file)
    anchor = "L$(pt.point.line)"
    return "$fn#$anchor"
end

fmtcount(total, suffix="") = x -> iszero(x) ? "" : "$x ($(round(Int, 100x/total)) %)$suffix"

lockfreeopenwrite(f, filename) = open(f, filename, write=true, lock=false)

output(r::Report, path) = begin
    mkpath(path)
    cp(templatefile("statprofiler.css"), joinpath(path, "statprofiler.css"), force=true)

    lockfreeopenwrite(joinpath(path, "index.html")) do io
        render_index(io; report=r)
    end

    lockfreeopenwrite(joinpath(path, "methods.html")) do io
        render_methods(io; report=r)
    end

    lockfreeopenwrite(joinpath(path, "files.html")) do io
        render_files(io; report=r)
    end

    lockfreeopenwrite(joinpath(path, "flamegraph.svg")) do io
        rng = StableRNG(1234)
        render_flamegraph(io; report=r, rng=rng)
    end

    for file in keys(r.traces_by_file)
        isnothing(file) && continue
        isfile(string(file)) || continue
        lines = [
            (LineNumberNode(i, file), code)
            for (i, code) in enumerate(eachline(string(file)))
        ]
        lockfreeopenwrite(joinpath(path, outputfilename(r, file))) do io
            render_sourcefile(io; filename=relpath(r, file), lines=lines, report=r)
        end
    end
end

end # module
