using Bounder
using Base.Test

@testset "utils" begin
    @test Bounder._tostr(nothing) == ""
    @test Bounder._tostr("something") == "something"
    @test Bounder._tostr(1) == "1"

    @test Bounder._coalesce(nothing, 1) == 1
    @test Bounder._coalesce(1, nothing) == 1
    @test Bounder._coalesce("a", "b") == "a"
end

@testset "primary" begin
    # TODO
end
