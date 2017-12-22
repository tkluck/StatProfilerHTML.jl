module StatProfilerHTML

export statprofilehtml

using Base.Profile

function statprofilehtml(data::Array{UInt,1} = UInt[],litrace::Dict{UInt,Array{StackFrame,1}} = Dict{UInt,Array{StackFrame,1}}())
    if length(data) == 0
        (data, litrace) = Profile.retrieve()
    end

    sharepath       = Pkg.dir("StatProfilerHTML", "share")
    statprofilehtml = Pkg.dir("StatProfilerHTML", "bin", "statprofilehtml")
    perllib         = Pkg.dir("StatProfilerHTML", "perllib")

    withenv("PERL5LIB" => perllib) do
        formatter, process =  open(`$statprofilehtml $sharepath`, "w", STDOUT)

        lastwaszero = false
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
                if !frame.from_c
                    file = Base.find_source_file(string(frame.file))
                    func_line = frame.line
                    if !isnull(frame.linfo)
                        linfo = get(frame.linfo)
                        func_line = linfo.def.line - 1  # off-by-one difference between how StatProfiler and julia seem to map this
                    end

                    write(formatter, "$(file)\t$(frame.line)\t$(frame.func)\t$(func_line)\n")
                    lastwaszero = false
                end
            end
        end
        close(formatter)
        wait(process)
    end
end

end
