using StatProfilerHTML

if VERSION >= v"0.7-"
    using Test
    using Profile
else
    using Base.Test
end

fibonacci(n) = n <= 2 ? 1 : fibonacci(n-1) + fibonacci(n-2)

@testset "StatPofilerHTML" begin
    mktempdir() do dir
        cd(dir) do
            @profile fibonacci(43)

            statprofilehtml()

            @test isdir("statprof")
        end
    end
end

@testset "C functions" begin
    mktempdir() do dir
        cd(dir) do
            @profile fibonacci(43)

            statprofilehtml(from_c=true)

            @test isdir("statprof")
        end
    end
end
