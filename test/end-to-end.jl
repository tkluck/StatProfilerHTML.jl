fibonacci(n) = n <= 2 ? 1 : fibonacci(n-1) + fibonacci(n-2)

@testset "End-to-end" begin
    @testset "statprofilehtml" begin
        mktempdir() do dir
            cd(dir) do
                @profile fibonacci(43)

                statprofilehtml()

                @test isdir("statprof")
            end
        end
    end

    @testset "statprofilehtml(from_c=true)" begin
        mktempdir() do dir
            cd(dir) do
                @profile fibonacci(43)

                statprofilehtml(from_c=true)

                @test isdir("statprof")
            end
        end
    end

    @testset "statprofilehtml(path=...)" begin
        mktempdir() do dir
            cd(dir) do
                @profile fibonacci(43)

                statprofilehtml(path="foobar")

                @test isdir("foobar")
                @test !isdir("statprof")
            end
        end
    end

    @testset "@profilehtml" begin
        mktempdir() do dir
            cd(dir) do
                @profilehtml fibonacci(43)

                @test isdir("statprof")
            end
        end
    end

    function searchdir(dir, pat)
        any(readdir(dir)) do path
            !isnothing(match(pat, path))
        end
    end

    @testset "Translate stdlib path" begin
        mktempdir() do dir
            cd(dir) do
                a = Vector{UInt8}(undef, 10000000)
                @profilehtml rand!(a, [1, 2, 3])

                @test isdir("statprof")
                @test searchdir("statprof", r"generation\.jl-.+")
            end
        end
    end
end
