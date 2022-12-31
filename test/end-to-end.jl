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
end
