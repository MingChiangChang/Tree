# TODO Parameter/Criteria for stopping
# 1. Low residual (good stop)
# 2. To many extra peaks (bad stop/killed)
#    Condition: norm(max.(fitted-data)./data) ?
#    Or is there anything better than 2 norm
using Combinatorics
using LinearAlgebra
using Base.Threads
using CrystalShift: reconstruct!

struct Tree{T, CP<:AbstractVector{T}, DP<:Int}
    nodes::CP
    depth::DP # Store for convenience
end

function Tree(phases::AbstractVector{<:PhaseTypes}, depth::Int)
    # Construct tree with certain depth
	T = eltype(phases)
    nodes = Node{<:T}[]
	root = Node{T}()
	push!(nodes, root)
    for d in 1:depth
		phase_combs = combinations(phases, d)
		nodes_at_level = get_nodes_at_level(nodes, d-1)
		for phases in phase_combs
			new_node = Node(phases)
			for old_node in nodes_at_level
			    if is_immidiate_child(old_node, new_node)
				    add_child!(old_node, new_node)
				    push!(nodes, new_node)
					break
                end
		    end
		end
    end
	Tree(nodes, depth)
end

Base.size(t::Tree) = size(t.nodes)
Base.getindex(t::Tree, i::Int) = Base.getindex(t.nodes, i)

function bft(t::Tree)
    # Breadth-first traversal, return an array of
	# Node with the b-f order
	traversal = Node[]
	for i in 1:t.depth
	    for node in t.nodes
            if get_level(node) == i
				push!(traversal, node)
			end
	    end
	end
	traversal
end

bft(t::Tree, level::Int) = get_nodes_at_level(t.nodes, level)

function dft(t::Tree)
    # Depth-first traversal, return an array of Node with
	# the D-F order
end

function search!(t::Tree, traversal_func::Function, x::AbstractVector,
	          y::AbstractVector, std_noise::Real, mean::AbstractVector,
			  std::AbstractVector, maxiter=32, regularization::Bool=true,
			  prunable::Function=(p, x, y, t)->false, tol::Real=1e-3)
	resulting_nodes = Vector{Vector{<:CrystalPhase}}()
	node_order = traversal_func(t)
	for level in 1:t.depth
        nodes = get_nodes_at_level(node_order, level)
		deleting = Set()
		@threads for node in nodes
		    @time phases = optimize!(node.current_phases, x, y, std_noise,
			          mean, std, maxiter=maxiter, regularization=regularization)
			push!(resulting_nodes, phases)
			if level<t.depth && prunable(phases, x, y, tol)
				println("Pruning...")
				push!(deleting, get_child_node_indicies(node, node_order)...)
			end
		end
		deleteat!(node_order, sort([deleting...]))
		println(size(node_order))
	end
	resulting_nodes
end

function search!(t::Tree, traversal_func::Function, x::AbstractVector,
	          y::AbstractVector, std_noise::Real, mean::AbstractVector,
			  std::AbstractVector, maxiter=32, regularization::Bool=true,
			  tol::Real=1e-3)
    node_order = traversal_func(t)
	@threads for node in node_order
        @time optimize!(node.current_phases, x, y, std_noise, mean, std,
                  maxiter=maxiter, regularization=regularization)
    end
end

# subtree
function remove_subtree!(nodes::AbstractVector{<:Node}, root_of_subtree::Node)
    # Given a vector of node and a node, remove
	# all the node that are child of the node
	# TODO Should remove there relationship as well??
	# TODO Will GC take care?
	to_be_removed = Int[]
    for (idx, node) in enumerate(nodes)
		if is_child(root_of_subtree, node) && root_of_subtree != node
			push!(to_be_removed, idx)
		end
	end
	deleteat!(nodes, to_be_removed)
end

function pos_res_thresholding(phases::AbstractVector{<:PhaseTypes},
	              x::AbstractVector, y::AbstractVector, tol::Real)
	# Only count extra peaks that showed up in reconstruction
    recon = zero(x)
	@simd for phase in phases
		recon += (phase).(x)
	end
	residual = norm(max.(recon-y, 0))
	return residual > tol
end
