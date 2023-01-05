
@testset "Reports" begin
    @testset "Empty report" begin
        r = Report(UInt[], Dict{UInt, Vector{StackFrame}}(), false, NOW)
        @test r isa Report
        @test isempty(r.traces_by_point)
        @test isempty(r.traces_by_function)
        @test r.tracecount == 0
        @test r.maxdepth == 0
    end

    @testset "Short report" begin
        r = TEST_REPORT
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
        @test r.sorted_files == [filename]
        @test r.tracecount == 2
        @test r.maxdepth == 3
    end
end
