__precompile__()

module Bounder

using Base.LibGit2
# using PkgDev

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
                   versions::Union{String,Vector{VersionNumber}}="all",
                   push::Bool=true)

    Pkg.installed(pkg) !== nothing || throw(ArgumentError("Package $pkg is not installed."))

    meta = LibGit2.GitRepo(Pkg.dir("METADATA"))

    LibGit2.isdirty(meta) && error("METADATA is dirty. Clean it up before running `setbounds`.")

    state = LibGit2.snapshot(meta)
    current_branch = LibGit2.branch(meta)

    try
        # Ensure that the new branch is always based on the default
        current_branch == "metadata-v2" || LibGit2.branch!(meta, "metadata-v2")

        LibGit2.branch!(meta, "setbounds-$pkg")
        bref = LibGit2.GitReference(meta, "refs/heads/setbounds-$pkg")

        alldirs = readdir(joinpath(LibGit2.path(meta), pkg, "versions"))
        vers = versions == "all" ? alldirs : alldirs ∩ map(string, versions)
        isempty(vers) && error("No versions to modify")

        const r::Regex = r"^\s*((@\w+)\s+)(\S+)(\s+([\d.]+)(\s+([\d.]+))?)?"
        # 2=platform 3=dependency 5=lower 7=upper

        for v in vers
            open(joinpath(LibGit2.path(meta), pkg, "versions", v, "requires"), "w") do f
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

        if !LibGit2.isdirty(meta)
            info("No changes have been made")
            LibGit2.branch!(meta, current_branch)
            LibGit2.delete_branch(bref)
            LibGit2.restore(state, meta)
            return
        end

        # Should be safe since we've ensured it wasn't dirty before our changes
        info("Committing changes...")
        # TODO: Add using LibGit2, dunno how
        run(`git add -u`)
        LibGit2.commit(meta, "Set version bounds on $dep for $pkg")

        if push
            info("Pushing to your remote...")
            remote = filter(s -> s != "origin", LibGit2.remotes(meta))[1]
            # TODO: Push using LibGit2.push(...)
            run(`git push $remote setbounds-$pkg`)
        end

        info("Putting everything back how we found it...")
        LibGit2.branch!(meta, current_branch)
        push && LibGit2.delete_branch(bref)
        LibGit2.restore(state, meta)

        info("Done! Now go make a pull request on JuliaLang/METADATA.jl.")
        # TODO: Create a PR using PkgDev.pull_request()

        return
    catch
        LibGit2.branch!(meta, current_branch)
        LibGit2.delete_branch(LibGit2.GitReference(meta, "refs/heads/setbounds-$pkg"))
        LibGit2.restore(state, meta)
        rethrow()
    end
end

end # module
