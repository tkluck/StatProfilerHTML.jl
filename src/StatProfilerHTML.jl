module StatProfilerHTML

export statprofilehtml

if VERSION >= v"0.7-"
    using Profile
    using Base.StackTraces: StackFrame
    with_value(f, x) = x !== nothing && f(x)
else
    using Compat: @info
    using Base.Profile
    with_value(f, x) = !isnull(x) && f(get(x))
    stdout = STDOUT
end

const basepath           = dirname(@__DIR__)
const sharepath          = joinpath(basepath, "share")
const statprofilehtml_pl = joinpath(basepath, "bin", "statprofilehtml.pl")
const perllib            = joinpath(basepath, "perllib")

function statprofilehtml(data::Array{UInt,1} = UInt[],litrace::Dict{UInt,Array{StackFrame,1}} = Dict{UInt,Array{StackFrame,1}}();
                         from_c=false)
    if length(data) == 0
        (data, litrace) = Profile.retrieve()
    end

    withenv("PERL5LIB" => perllib) do
        open(`perl $statprofilehtml_pl $sharepath`, "w", stdout) do formatter
            lastwaszero = true
            for d in data
                if d == 0
                    if !lastwaszero
                        write(formatter, "\n")
                    end
                    lastwaszero = true
                    continue
                end
                # I don't understand the semantics of having more than one value in the array. Take
                # all of them
                frames= litrace[d]
                for frame in frames
                  if !frame.from_c || from_c
                        file = Base.find_source_file(string(frame.file))
                        func_line = frame.line
                        with_value(frame.linfo) do linfo
                            func_line = linfo.def.line - 1  # off-by-one difference between how StatProfiler and julia seem to map this
                        end

                        file_repr = file == nothing ? "nothing" : file
                        write(formatter, "$(file_repr)\t$(frame.line)\t$(frame.func)\t$(func_line)\n")
                        lastwaszero = false
                    end
                end
            end
        end
    end

    @info "Wrote profiling output to file://$(pwd())/statprof/index.html"
end

end
