import Base.StackTraces: StackFrame
import StatProfilerHTML.Reports: Report, TracePoint, TraceCounts

@testset "Reports" begin
    @testset "Empty report" begin
        r = Report(UInt[], Dict{UInt, Vector{StackFrame}}(), false)
        @test r isa Report
        @test isempty(r.traces_by_point)
        @test isempty(r.traces_by_function)
        @test r.tracecount == 0
        @test r.maxdepth == 0
    end

    @testset "Short report" begin
        filename = :var"/home/my/file"
        sf1 = StackFrame(:helper_function, filename, 22)
        sf2 = StackFrame(:main_function, filename, 42)
        tp1 = TracePoint(sf1)
        tp2 = TracePoint(sf2)
        fp1 = tp1.containing_function
        fp2 = tp2.containing_function
        ip1 = UInt64(0x22)
        ip2 = UInt64(0x42)
        sep = UInt64[1, 1, 1, 1, 0, 0]
        r = Report(UInt64[ip1, ip2, sep..., ip2, sep...], Dict(ip1 => [sf1], ip2 => [sf2]), false)
        @test r isa Report
        @testset "Traces by point" begin
            @test r.traces_by_point[tp1.point] == TraceCounts(1, 1)
            @test r.traces_by_point[tp2.point] == TraceCounts(2, 1)
        end
        @testset "Traces by function" begin
            @test r.traces_by_function[fp1] == TraceCounts(1, 1)
            @test r.traces_by_function[fp2] == TraceCounts(2, 1)
        end
        @testset "Traces by file" begin
            @test_broken r.traces_by_file[filename] == TraceCounts(2, 2)
        end
        @testset "Callers and callees" begin
            @test r.callsites[fp1.point][tp2] == TraceCounts(1, 1)
            @test r.callees[tp2.point][fp1] == 1
        end
        @test r.tracecount == 2
        @test r.maxdepth == 2
    end
end
