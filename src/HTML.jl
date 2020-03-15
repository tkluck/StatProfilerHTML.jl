module HTML

import Base64: base64encode

import Dates: format, RFC1123Format
import HAML: includehaml, @include
import ProfileSVG

import ..Reports: Report, FunctionPoint, TracePoint

templatefile(name...) = joinpath(@__DIR__, "..", "haml", name...)

includehaml(@__MODULE__, :render_sourcefile, templatefile("sourcefile.hamljl"))
includehaml(@__MODULE__, :render_index, templatefile("index.hamljl"))
includehaml(@__MODULE__, :render_files, templatefile("files.hamljl"))
includehaml(@__MODULE__, :render_methods, templatefile("methods.hamljl"))

outputfilename(::Nothing) = ""
outputfilename(sourcefile::Symbol) = begin
    b = basename(string(sourcefile))
    x = base64encode(string(sourcefile))
    return "$b-$x.html"
end

href(pt::FunctionPoint) = begin
    fn = outputfilename(pt.point.file)
    anchor = "L$(pt.point.line)"
    return "$fn#$anchor"
end

href(pt::TracePoint) = begin
    fn = outputfilename(pt.point.file)
    anchor = "L$(pt.point.line)"
    return "$fn#$anchor"
end

output(r::Report, path) = begin
    mkpath(path)
    cp(templatefile("statprofiler.css"), joinpath(path, "statprofiler.css"), force=true)

    open(joinpath(path, "index.html"), "w") do io
        render_index(io; report=r)
    end

    open(joinpath(path, "methods.html"), "w") do io
        render_methods(io; report=r)
    end

    open(joinpath(path, "files.html"), "w") do io
        render_files(io; report=r)
    end

    ProfileSVG.save("statprof/flamegraph.svg", r.flamegraph)

    for file in keys(r.traces_by_file)
        isnothing(file) && continue
        isfile(string(file)) || continue
        lines = [
            (LineNumberNode(i, file), code)
            for (i, code) in enumerate(readlines(string(file)))
        ]
        open(joinpath(path, outputfilename(file)), "w") do io
            render_sourcefile(io; filename=file, lines=lines, report=r)
        end
    end
end

end # module
