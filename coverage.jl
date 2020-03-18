#!/usr/bin/env julia

using Pkg
Pkg.add("Coverage")

using Coverage

coveragecounts = Coverage.FileCoverage[]

addfolder(folder) = for (root, _, files) in walkdir(folder)
    covered_files = Set(replace(f, r"\.\d+\.cov\z" => "") for f in files)
    to_process= intersect(files, covered_files)
    for file in to_process
        ENV["DISABLE_AMEND_COVERAGE_FROM_SRC"] = endswith(file, ".jl") ? "no" : "yes"
        push!(coveragecounts, Coverage.process_file(joinpath(root, file), root))
    end
end

addfolder("src")
addfolder("haml")

Coverage.Codecov.submit(coveragecounts)
