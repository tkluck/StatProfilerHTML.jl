import Dates: DateTime, @dateformat_str
import StatProfilerHTML.HTML: output

const GOLDENDIR = joinpath(@__DIR__, "golden")

@testset "HTML" begin
    if "--update-golden" in ARGS
        if isfile(GOLDENDIR)
            mv(GOLDENDIR, "$GOLDENDIR.bak", force=true)
        end
        output(TEST_REPORT, GOLDENDIR)
    else
        @info "For updating the golden output, pass --update-golden to the test script"
    end

    mktempdir() do resultdir
        output(TEST_REPORT, resultdir)

        for (root, dirs, files) in walkdir(resultdir)
            for file in files
                rel = relpath(root, resultdir)
                lhs = joinpath(resultdir, rel, file)
                rhs = joinpath(GOLDENDIR, rel, file)
                @test isfile(rhs)
                diff = readchomp(Cmd(`diff -u $lhs $rhs`, ignorestatus=true))
                if isempty(diff)
                    @test true
                else
                    @test false
                    @error diff
                end
            end
        end

        for (root, dirs, files) in walkdir(GOLDENDIR)
            for file in files
                @test isfile(joinpath(resultdir, root, file))
            end
        end
    end

    @testset "Empty report" begin
        mktempdir() do resultdir
            r = Report(UInt64[], Dict{UInt64, Vector{StackFrame}}(), false, NOW)
            output(r, resultdir)
            @test isfile(joinpath(resultdir, "index.html"))
       end
   end
end
