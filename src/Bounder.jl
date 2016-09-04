__precompile__()

module Bounder

using Git

export setbounds

# Avoids string(nothing) == "nothing"
_tostr(x::Any) = ifelse(x === nothing, "", string(x))

# First non-void value
_coalesce(a, b) = ifelse(a === nothing, ifelse(b === nothing, nothing, b), a)


"""
    setbounds(pkg, dep; lower=nothing, upper=nothing, versions="all")

Set upper and/or lower bounds on the dependency `dep` for package `pkg`, for
each version of `pkg` specified in `versions`.
"""
function setbounds(pkg::String,
                   dep::String;
                   lower::Union{VersionNumber,Void}=nothing,
                   upper::Union{VersionNumber,Void}=nothing,
                   versions::Union{String,Vector{VersionNumber}}="all")

    Pkg.installed(pkg) !== nothing || throw(ArgumentError("Package $pkg is not installed."))

    const metadir::String = Pkg.dir("METADATA")

    Git.dirty(dir=metadir) && error("METADATA is dirty. Clean it up before running `setbounds`.")

    state = Git.snapshot(dir=metadir)

    try
        cd(metadir) do
            # Ensure that the new branch is always based on the default
            current_branch = Git.branch()
            current_branch == "metadata-v2" || run(`git checkout metadata-v2`)

            run(`git checkout -b setbounds-$pkg`)

            vers = if versions == "all"
                readdir(joinpath(pwd(), pkg, "versions"))
            else
                map(string, versions)
            end

            const r::Regex = r"^\s*((@\w+)\s+)(\S+)(\s+([\d.]+)(\s+([\d.]+))?)?"
            # 2=platform 3=dependency 5=lower 7=upper

            for v in vers
                open(joinpath(pwd(), pkg, "versions", v, "requires"), "w") do f
                    for line in eachline(f)
                        m = match(r, line)

                        if m !== nothing && m.captures[3] == dep
                            platform, _lower, _upper = m.captures[[2,5,7]]

                            # Behold the secret mutability of strings! Muahaha
                            Base.chomp!(line)

                            _lower = _tostr(_coalesce(lower, _lower))
                            _upper = _tostr(_coalesce(upper, _upper))

                            newline = strip(join([_tostr(platform), dep, _lower, _upper], " "))

                            # Preserve comments at the end of the line, if any
                            comment_ind = findfirst(line, '#')
                            comment_ind > 0 && (newline *= " " * line[commend_ind:end])

                            # The line has been `chomp`ed, so we need the ln
                            println(f, newline)
                        else
                            print(f, line)
                        end
                    end
                end
            end

            if !Git.dirty()
                info("No changes have been made")
                run(`git checkout $current_branch`)
                run(`git branch -D setbounds-$pkg`)
                Git.restore(state)
                return nothing
            end

            # Should be safe since we've ensured it wasn't dirty before our changes
            info("Committing changes...")
            run(`git add -u`)
            run(`git commit -m "Set bounds on $dep for $pkg"`)

            info("Pushing to your remote...")
            remote = filter(s -> s != "origin", split(readchomp(`git remote`), "\n"))[1]
            run(`git push $remote setbounds-$pkg`)

            # It exists on the remote, unnecessary locally
            info("Putting everything back how we found it...")
            run(`git checkout $current_branch`)
            run(`git branch -D setbounds-$pkg`)
        end

        Git.restore(state, dir=metadir)
        info("Done! Now go make a pull request on JuliaLang/METADATA.jl.")

        return nothing
    catch
        Git.restore(state, dir=metadir)
        rethrow()
    end
end

end # module
