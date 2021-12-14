module CrystalTree
using CrystalShift: CrystalPhase, optimize!
using PhaseMapping: Phase

export Node, Tree
const RealOrVec = Union{Real, AbstractVector{<:Real}}

include("util.jl")
include("node.jl")
include("tree.jl")
include("search.jl")
include("probabilistic.jl")

end
