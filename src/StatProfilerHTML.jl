module StatProfilerHTML

export statprofilehtml, @profilehtml

include("Reports.jl")
include("HTML.jl")

import Base.StackTraces: StackFrame
import Profile
import Profile: LineInfoDict

import .Reports: Report
import .HTML: output

function statprofilehtml(data::Vector{<:Unsigned} = UInt[], litrace::LineInfoDict = LineInfoDict();
                         from_c=false, path="statprof")
    if length(data) == 0
        (data, litrace) = Profile.retrieve()
    end

    fullpath = abspath(path)

    report = Report(data, litrace, from_c)
    sort!(report)
    HTML.output(report, path)

    @info "Wrote profiling output to file://$fullpath/index.html ."
end

macro profilehtml(expr)
    quote
        Profile.clear()
        res = try
            Profile.@profile $(esc(expr))
        catch ex
            ex isa InterruptException || rethrow(ex)
            @info "You interrupted the computation; generating profiling view for the computation so far."
        end
        statprofilehtml()
        res
    end
end

precompile(Tuple{typeof(statprofilehtml)})

end
