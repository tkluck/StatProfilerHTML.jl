using StatProfilerHTML

using Test
using Profile

using Base.StackTraces: StackFrame
using Dates: DateTime, @dateformat_str
using StatProfilerHTML.Reports: DUMMY_SEPARATOR, Report, TracePoint, TraceCounts

const NOW = DateTime("2022-12-31", dateformat"y-m-d")

const TEST_REPORT = begin
    filename = :var"/home/my/file"
    sf1 = StackFrame(:helper_function, filename, 22)
    sf2 = StackFrame(:main_function, filename, 42)
    tp1 = TracePoint(sf1)
    tp2 = TracePoint(sf2)
    fp1 = tp1.containing_function
    fp2 = tp2.containing_function
    ip1 = UInt64(0x22)
    ip2 = UInt64(0x42)
    sep = DUMMY_SEPARATOR
    r = Report(UInt64[ip1, ip2, sep..., ip2, sep...], Dict(ip1 => [sf1], ip2 => [sf2]), false, NOW)
    sort!(r)
end

@testset "StatProfilerHTML" begin
    include("Reports.jl")
    include("HTML.jl")
    include("end-to-end.jl")
end
