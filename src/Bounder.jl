__precompile__()

module Bounder

using Base.LibGit2

export setbounds

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

    lower === upper === nothing && throw(ArgumentError("a lower or upper bound must be specified"))

    const META_DIR::String = Pkg.dir("METADATA")

    isdir(joinpath(META_DIR, pkg)) || throw(ArgumentError("package $pkg not found in METADATA"))

    LibGit2.transact(LibGit2.GitRepo(META_DIR)) do meta

        LibGit2.isdirty(meta) && error("METADATA is dirty. Clean it up before running `setbounds`.")

        current_branch = LibGit2.branch(meta)

        # Do work on the default branch so that PRs can be submitted with PkgDev.publish()
        current_branch == "metadata-v2" || LibGit2.branch!(meta, "metadata-v2")

        alldirs = readdir(joinpath(LibGit2.path(meta), pkg, "versions"))
        vers = versions == "all" ? alldirs : intersect(alldirs, map(string, versions))
        isempty(vers) && error("No versions to modify")

        for v in vers
            reqfile = joinpath(LibGit2.path(meta), pkg, "versions", v, "requires")
            olddeps = Pkg.Reqs.read(reqfile)

            newdeps = Vector{Pkg.Reqs.Line}()

            for line in olddeps
                if isa(line, Pkg.Reqs.Requirement) && line.package == dep
                    # Can this actually happen in a requires file??
                    if length(line.versions.intervals) != 1
                        error("possibly malformed version specification for $dep in $pkg $v requires")
                    end

                    existing_lower = line.versions.intervals[1].lower
                    existing_upper = line.versions.intervals[1].upper

                    new_lower = lower === nothing ? existing_lower : lower
                    new_upper = upper === nothing ? existing_upper : upper

                    new_bounds = Pkg.Types.VersionInterval(new_lower, new_upper)
                    vset = Pkg.Types.VersionSet(Pkg.Types.VersionInterval[new_bounds])

                    push!(newdeps, Pkg.Reqs.Requirement(dep, vset, line.system))
                else
                    push!(newdeps, line)
                end
            end

            if newdeps != olddeps
                Pkg.Reqs.write(reqfile, newdeps)
                LibGit2.add!(meta, reqfile)
            end
        end

        LibGit2.with(LibGit2.GitStatus, meta) do status
            if length(status) == 0
                info("No changes were made to METADATA")
                return
            end
        end

        LibGit2.isdirty(meta) || error("changes not staged for commit")

        info("Committing changes...")
        LibGit2.commit(meta, "Set version bounds on $dep for $pkg")

        info("Done! Submit your changes upstream using `PkgDev.publish()`.")

        return
    end
end

end # module
