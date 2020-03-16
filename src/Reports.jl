module Reports

import Base.StackTraces: StackFrame
import Dates: now
import Profile

import DataStructures: DefaultDict
import FlameGraphs: flamegraph

struct FunctionPoint
    point :: LineNumberNode
    name  :: Symbol
end

struct TracePoint
    containing_function :: FunctionPoint
    point               :: LineNumberNode
    from_c              :: Bool
end

TracePoint(frame::StackFrame) = begin
    file = Base.find_source_file(string(frame.file))
    file = isnothing(file) ? nothing : Symbol(file)

    func_line = isnothing(frame.linfo) ? frame.line : frame.linfo.def.line - 1

    return TracePoint(
        FunctionPoint(LineNumberNode(Int(func_line), file), frame.func),
        LineNumberNode(Int(frame.line), file),
        frame.from_c
    )
end

mutable struct TraceCounts
    inclusive :: Int
    exclusive :: Int
end

TraceCounts() = TraceCounts(0, 0)

mutable struct Report
    traces_by_point
    traces_by_function
    traces_by_file
    sorted_functions
    sorted_files
    callsites
    callees
    functionnames
    tracecount
    flamegraph
    maxdepth
    generated_on
end

Report() = Report(
    DefaultDict{LineNumberNode, TraceCounts}(TraceCounts),
    DefaultDict{FunctionPoint, TraceCounts}(TraceCounts),
    DefaultDict{Union{Nothing, Symbol}, TraceCounts}(TraceCounts),
    FunctionPoint[],
    Symbol[],
    DefaultDict{LineNumberNode, DefaultDict{TracePoint, TraceCounts}}(() -> DefaultDict{TracePoint, TraceCounts}(TraceCounts)),
    DefaultDict{LineNumberNode, DefaultDict{FunctionPoint, Int}}(() -> DefaultDict{FunctionPoint, Int}(() -> 0)),
    DefaultDict{LineNumberNode, Symbol}(() -> Symbol("#error: no name#")),
    0,
    nothing,
    0,
    now(),
)


Report(data::Vector{UInt}, litrace::Dict{UInt, Vector{StackFrame}}, from_c) = begin
    report = Report()

    report.flamegraph = flamegraph(data, lidict=litrace, C=from_c)

    data, litrace = Profile.flatten(data, litrace)

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

    return report
end

Base.push!(r::Report, trace::Vector{StackFrame}) = begin
    for frame in trace
        pt = TracePoint(frame)
        r.traces_by_point[pt.point].inclusive += 1
        r.traces_by_function[pt.containing_function].inclusive += 1
        r.traces_by_file[pt.point.file].inclusive += 1

        r.functionnames[pt.containing_function.point] = pt.containing_function.name
    end

    length(trace) > 0 && let frame = trace[1]
        pt = TracePoint(frame)
        r.traces_by_point[pt.point].exclusive += 1
        r.traces_by_function[pt.containing_function].exclusive += 1
        r.traces_by_file[pt.point.file].exclusive += 1
    end

    for (callee, caller) in @views zip(trace[1:end-1], trace[2:end])
        caller = TracePoint(caller)
        callee = TracePoint(callee).containing_function

        r.callsites[callee.point][caller].inclusive += 1
        r.callees[caller.point][callee] += 1
    end

    length(trace) > 1 && let (callee, caller) = (trace[1], trace[2])
        caller = TracePoint(caller)
        callee = TracePoint(callee).containing_function

        r.callsites[callee.point][caller].exclusive += 1
    end

    r.tracecount += 1
    r.maxdepth = max(r.maxdepth, length(trace))

    return r
end

Base.sort!(r::Report) = begin
    r.sorted_functions = collect(keys(r.traces_by_function))
    sort!(r.sorted_functions, by=fn -> r.traces_by_function[fn].exclusive, rev=true)

    r.sorted_files = collect(keys(r.traces_by_file))
    sort!(r.sorted_files, by=file -> r.traces_by_file[file].exclusive, rev=true)

    return r
end


end # module
