module StatProfilerHTML

export statprofilehtml, @profilehtml

include("Reports.jl")
include("HTML.jl")

import .Reports: Report
import .HTML: output

using Profile
using Base.StackTraces: StackFrame

function statprofilehtml(data::Vector{UInt} = UInt[],litrace::Dict{UInt64, Vector{StackFrame}} = Dict{UInt64, Vector{StackFrame}}();
                         from_c=false)
    if length(data) == 0
        (data, litrace) = Profile.retrieve()
    end

    report = Report(data, litrace, from_c)
    sort!(report)
    HTML.output(report, "statprof")

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
