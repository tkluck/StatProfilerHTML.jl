using StatProfilerHTML
using Random

using Test
using Profile

using Base.StackTraces: StackFrame
using Dates: DateTime, @dateformat_str
using StatProfilerHTML.Reports: DUMMY_SEPARATOR, Report, TracePoint, TraceCounts

const NOW = DateTime("2022-12-31", dateformat"y-m-d")
const STARTPATH = @__DIR__

const TEST_REPORT = begin
    filename = Symbol(joinpath(STARTPATH, "fake-source.jl"))
    dangling_filename = Symbol(joinpath(STARTPATH, "non-existing-source.jl"))
    sf1 = StackFrame(:helper_function, filename, 8)
    sf2 = StackFrame(:main_function, filename, 15)
    sf3 = StackFrame(:hidden_function, dangling_filename, 20)
    tp1 = TracePoint(sf1)
    tp2 = TracePoint(sf2)
    tp3 = TracePoint(sf3)
    fp1 = tp1.containing_function
    fp2 = tp2.containing_function
    ip1 = UInt64(0x22)
    ip2 = UInt64(0x42)
    ip2 = UInt64(0x42)
    ip3 = UInt64(0x43)
    sep = DUMMY_SEPARATOR
    r = Report(UInt64[ip1, ip2, sep..., ip2, sep..., ip3, ip2, sep...], Dict(ip1 => [sf1], ip2 => [sf2], ip3 => [sf3]), false, NOW, STARTPATH)
end

@testset "StatProfilerHTML" begin
    include("Reports.jl")
    include("HTML.jl")
    include("end-to-end.jl")
end
