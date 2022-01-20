module Testnode
using CrystalTree: Node, add_child!, get_nodes_at_level
using CrystalTree: is_immidiate_child, is_child, get_level
using CrystalTree: get_phase_ids
using CrystalShift: CrystalPhase
using Test

# CrystalPhase object creation
path = "../data/"
phase_path = path * "sticks.csv"
f = open(phase_path, "r")

if Sys.iswindows()
    s = split(read(f, String), "#\r\n") # Windows: #\r\n ...
else
    s = split(read(f, String), "#\n")
end

if s[end] == ""
    pop!(s)
end

cs = Vector{CrystalPhase}(undef, size(s))
@. cs = CrystalPhase(String(s))
println("$(size(cs, 1)) phase objects created!")

# Creating objects for testing
root = Node{CrystalPhase}()
node1 = Node(cs[1], 2)
node2 = Node([cs[1], cs[2]], 3)
node3 = Node([cs[1], cs[2]], 4)
node4 = Node([cs[1], cs[2], cs[3]], 5)

add_child!(root, node1)
add_child!(node1, node2)
fake_tree = [root, node1, node2, node3, node4]

@testset "Basic Node properties" begin
    @test is_immidiate_child(node1, node2)
    @test node2 == node3
    @test node1 != node3
    @test is_child(node1, node2)
    @test is_child(node1, node4) # two level down
    @test root.child_node == [node1]
    @test root.child_node[1].child_node == [node2]
    @test is_immidiate_child(node1, node2)
    @test is_immidiate_child(node2, node4)
    @test !is_immidiate_child(node1, node4)
    @test get_level(node4) == 3
    @test get_phase_ids(node4) == [0, 1, 2]
    @test get_nodes_at_level(fake_tree, 3) == [node4]
end

end # module