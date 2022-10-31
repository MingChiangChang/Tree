using CrystalShift
using CrystalTree
using CrystalTree: Lazytree, search!, approximate_negative_log_evidence, get_phase_ids
using CrystalShift: Lorentz, get_free_lattice_params, extend_priors, get_free_params
using Combinatorics
using ProgressBars
using Measurements
using NPZ

using Plots

# std_noise = .01
# std_noises = [.01, .03, .05, .07, .09]
std_noises = [.03, .04, .05, 0.06, 0.07]
mean_θ = [1., .5, .1]
std_θ = [.05, .05, .05]

for std_noise in std_noises

    function get_probabilities(results::AbstractVector,
                            x::AbstractVector,
                            y::AbstractVector,
                            mean_θ::AbstractVector,
                            std_θ::AbstractVector)
        prob = zeros(length(results))
        for i in 1:length(results)
            θ = get_free_params(results[i].phase_model)
            # println(θ)
            # orig = [p.origin_cl for p in result[i].phase_model]
            full_mean_θ, full_std_θ = extend_priors(mean_θ, std_θ, results[i].phase_model.CPs)
            prob[i] = approximate_negative_log_evidence(results[i], θ, x, y, std_noise, full_mean_θ, full_std_θ, "LS")
        end
        prob ./= minimum(prob) * std_noise
        exp.(-prob) ./ sum(exp.(-prob))
    end

    function get_bin(prob)
        if isnan(prob)
            p = 1
        else
            p = Int64(floor(prob*10))+1
        end
        if p > 10
            p = 10
        end
        # println("$(prob) $(p)")
        return p
    end

    function get_mod_phase_ids(pm)
        ids = get_phase_ids(pm)
        for i in eachindex(ids)
            ids[i] += 1
        end
        Set(ids)
    end



    # std_noise = .1
    # mean_θ = [1., 1., .1]
    # std_θ = [0.05, 5., .3]

    test_path = "/Users/ming/Desktop/Code/CrystalShift.jl/data/calibration/sticks.csv"
    data_path = "/Users/ming/Desktop/Code/CrystalTree.jl/data/calibration_data_nl=1e-1.npy"
    test_data = npzread(data_path)
    f = open(test_path, "r")

    if Sys.iswindows()
        s = split(read(f, String), "#\r\n") # Windows: #\r\n ...
    else
        s = split(read(f, String), "#\n")
    end

    if s[end] == ""
        pop!(s)
    end

    cs = Vector{CrystalPhase}(undef, size(s))
    cs = @. CrystalPhase(String(s), (0.1, ), (Lorentz(), ))
    x = collect(8:.1:40)
    totl = zeros(Int64, 10)
    correct = zero(totl)
    totl_prob = zeros(Float64, 10)

    phase_correct = zeros(Int64, 10)
    phase_totl = zeros(Int64, 10)

    k = 2
    runs = 100000
    correct_count = 0

    for i in tqdm(1:runs)
        # test_comb = comb[rand(1:length(comb), 1)][1]
        cs = Vector{CrystalPhase}(undef, size(s))
        cs = @. CrystalPhase(String(s), (0.1, ), (Lorentz(), ))
        y = test_data[i, 1:end-2]
        test_comb = test_data[i, end-1:end]
        if test_comb[end] == 0.0
            pop!(test_comb)
        end
        test_comb = Set(test_comb)

        LT = Lazytree(cs, k, x, 5, s)

        results = search!(LT, x, y, k, std_noise, mean_θ, std_θ,
                        method=LM, objective="LS", maxiter=256,
                        regularization=true)
        results = reduce(vcat, results)
        probs = get_probabilities(results, x, y, mean_θ, std_θ)

        prob_of_phase = zeros(Float64, 5)
        for j in eachindex(results)
            for k in eachindex(results[j].phase_model.CPs)
                ind = results[j].phase_model.CPs[k].id + 1
                prob_of_phase[ind] += probs[j]
            end
        end

        for j in eachindex(prob_of_phase)
            ind = get_bin(prob_of_phase[j])
            phase_totl[ind] += 1
            if j in test_comb
                phase_correct[ind] += 1
            end
        end

        ind = argmax(probs)
        ss = Set([results[ind].phase_model.CPs[i].id+1 for i in eachindex(results[ind].phase_model.CPs)])
        answer = test_comb
        # ss == answer && (global correct_count += 1)
        ss == answer && (correct_count += 1)

        # println(get_mod_phase_ids(results[ind]))
        # println(test_comb)
        # plt = plot(x, y)
        # plot!(x, evaluate!(zero(x), results[ind].phase_model, x))
        # display(plt)

        for j in eachindex(results)
            bin_num = get_bin(probs[j])
            totl[bin_num] += 1
            totl_prob[bin_num] += probs[j]
            if get_mod_phase_ids(results[j]) == test_comb
                correct[bin_num] += 1
            end
        end

        # for i in eachindex(cs)
        #     println("$(cs[i].name): $(prob_of_phase[i])")
        # end
    end

    using Statistics: cor
    pearson = cor([0.05+0.1*i for i in 0:9], correct./totl)

    plt = plot([0., 1.], [0., 1.],
            linestyle=:dash, color=:black,
            legend=false, figsize=(10,10), dpi=300,
            xlims=(0, 1), ylims=(0, 1), xtickfontsize=10, ytickfontsize=10,
            xlabelfontsize=12, ylabelfontsize=12, markersize=5,
            title="k=$(k)\nstd_noise=$(std_noise), mean=$(mean_θ)\n std=$(std_θ)\n runs=$(runs) pearson=$(pearson)\n accuracy=$(correct_count/runs)")

    calibration = correct ./ totl

    for i in eachindex(calibration)
        if isnan(calibration[i])
            calibration[i] = 0
        end
    end

    plot!(collect(0.05:.1: 0.95), calibration)
    scatter!(collect(0.05:.1: 0.95), calibration)
    plot!(totl_prob ./ totl, calibration)
    scatter!(totl_prob ./ totl, calibration)

    font(20)
    xlabel!("Predicted probabilities")
    ylabel!("Frequency of correct matches")
    display(plt)
    savefig("Calibration_std_noise=$(std_noise)_mean=$(mean_θ)_std=$(std_θ)_runs=$(runs)_pearson=$(pearson)_accuracy=$(correct_count/runs).png")

    pearson = cor([0.05+0.1*i for i in 0:9], phase_correct./phase_totl)

    plt = plot([0., 1.], [0., 1.],
            linestyle=:dash, color=:black,
            legend=false, figsize=(10,10), dpi=300,
            xlims=(0, 1), ylims=(0, 1), xtickfontsize=10, ytickfontsize=10,
            xlabelfontsize=12, ylabelfontsize=12, markersize=5,
            title="k=$(k)\nstd_noise=$(std_noise), mean=$(mean_θ)\n std=$(std_θ)\n runs=$(runs) pearson=$(pearson)\n accuracy=$(correct_count/runs)")

    calibration = phase_correct ./ phase_totl

    for i in eachindex(calibration)
        if isnan(calibration[i])
            calibration[i] = 0
        end
    end

    plot!(collect(0.05:.1: 0.95), calibration)
    scatter!(collect(0.05:.1: 0.95), calibration)

    plot!(totl_prob ./ totl, calibration)
    scatter!(totl_prob ./ totl, calibration)

    font(20)
    xlabel!("Predicted phase probabilities")
    ylabel!("Frequency of correct phase matches")
    display(plt)
    savefig("Calibration_phase_std_noise=$(std_noise)_mean=$(mean_θ)_std=$(std_θ)_runs=$(runs)_pearson=$(pearson)_accuracy=$(correct_count/runs).png")

    t = Dict{Any, Any}()
    t["std_noise"] = std_noise
    t["mean_theta"] = mean_θ
    t["std_theta"] = std_θ
    t["runs"] = runs
    t["accuracy"] = correct_count/runs
    t["totl"] = totl
    t["correct"] = correct
    t["phase_correct"] = phase_correct
    t["totl_prob"] = totl_prob
    t["phase_totl"] = phase_totl

    using JSON
    using Dates

    open("Noise=0.1_test_$(Dates.format(now(), "yyyy-mm-dd_HH:MM")).json", "w") do f
        JSON.print(f, t)
    end
end