using StatProfilerHTML

using Test
using Profile

@testset "StatProfilerHTML" begin
    include("Reports.jl")
    include("HTML.jl")
    include("end-to-end.jl")
end
