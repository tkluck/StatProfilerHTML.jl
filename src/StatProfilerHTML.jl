module StatProfilerHTML

export statprofilehtml, @profilehtml

include("Reports.jl")
include("HTML.jl")

import .Reports: Report
import .HTML: output

using Profile
using Base.StackTraces: StackFrame

import FlameGraphs: flamegraph
import ProfileSVG

function statprofilehtml(data::Array{UInt,1} = UInt[],litrace::Dict{UInt,Array{StackFrame,1}} = Dict{UInt,Array{StackFrame,1}}();
                         from_c=false)
    if length(data) == 0
        (data, litrace) = Profile.retrieve()
    end

    data, litrace = Profile.flatten(data, litrace)

    report = Report()
    lastwaszero = true
    trace = StackFrame[]
    for d in data
        if d == 0
            if !lastwaszero
                push!(report, trace)
                empty!(trace)
            end
            lastwaszero = true
            continue
        end
        frame = litrace[d]
        if !frame.from_c || from_c
            push!(trace, frame)
            lastwaszero = false
        end
    end

    sort!(report)
    HTML.output(report, "statprof")

    fg = flamegraph(data, lidict=litrace, C=from_c)
    ProfileSVG.save("statprof/flamegraph.svg", fg)

    @info "Wrote profiling output to file://$(pwd())/statprof/index.html ."
end

macro profilehtml(expr)
    quote
        Profile.clear()
        res = try
            @profile $(esc(expr))
        catch ex
            ex isa InterruptException || rethrow(ex)
            @info "You interrupted the computation; generating profiling view for the computation so far."
        end
        statprofilehtml()
        res
    end
end

end
