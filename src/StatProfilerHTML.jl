module StatProfilerHTML

export statprofilehtml

using Base.Profile

beacon() = "dummy function to use functionloc for finding the path"
pkg_basepath() = dirname(dirname(functionloc(beacon)[1]))

function statprofilehtml(data::Array{UInt,1} = UInt[],litrace::Dict{UInt,Array{StackFrame,1}} = Dict{UInt,Array{StackFrame,1}}())
    if length(data) == 0
        (data, litrace) = Profile.retrieve()
    end

    basepath = pkg_basepath()

    withenv("PERL5LIB" => "$basepath/perllib") do
        formatter, process =  open(`$basepath/bin/statprofilehtml`, "w", STDOUT)

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
    end
end

end
