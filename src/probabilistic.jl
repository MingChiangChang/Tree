#const RealOrVec = Union{Real, AbstractVector{<:Real}}
# computes log marginal likelihood of θ given (x, y) based on the Laplace approximation
# NOTE: the input θ should be the local minimum with respect to θ
# mean_θ, std_θ are the mean and standard deviation of the prior Gaussian distribution of θ
function log_marginal_likelihood(node::Node, θ::AbstractVector, x::AbstractVector,
								 y::AbstractVector, std_noise::RealOrVec,
								 mean_θ::RealOrVec, std_θ::RealOrVec)
	log_θ = log.(θ)
	H = hessian_of_objective_wrt_log(node, log_θ, x, y, std_noise, mean_θ, std_θ)
	# calculate marginal likelihood
	Σ⁻¹ = H # reinterpret Hessian of minimization problem as inverse of covariance matrix
	negative_log_marginal_likelihood(Σ⁻¹, log_θ) # TODO: do we need to scale by "height" of distribution?
end

# computes Hessian of objective function - including regularzation - w.r.t. θ
# useful for Laplace approximation
# NOTE: if we want to use a separate std_noise for each q value, need to
# modify the residual function
function hessian_of_objective(node::Node, θ::AbstractVector, x::AbstractVector,
							  y::AbstractVector, std_noise::RealOrVec,
							  mean_θ::RealOrVec, std_θ::RealOrVec)
	function f(θ)
		sos_objective(node, θ, x, y, std_noise) + regularizer(θ, mean_θ, std_θ)
	end
	
	ForwardDiff.hessian(f, θ)
end

# sos = sum of squares
function sos_objective(node::Node, θ::AbstractVector, x::AbstractVector,
	y::AbstractVector, std_noise::RealOrVec)
	r = similar(y)
	r = _residual!(node.current_phases, log.(θ), x, y, r, std_noise)
	return sum(abs2, r)
end

# regularizer in log space
function regularizer(θ::AbstractVector, mean_θ::RealOrVec, std_θ::RealOrVec)
	p = similar(θ)
	sum(abs2, _prior(p, log.(θ), mean_θ, std_θ))
end

function hessian_of_objective_wrt_log(node::Node, log_θ::AbstractVector, x::AbstractVector,
									  y::AbstractVector, std_noise::RealOrVec,
									  mean_θ::RealOrVec, std_θ::RealOrVec)
	function f(θ)
		sos_log_objective(node, log_θ, x, y, std_noise) + log_regularizer(θ, mean_θ, std_θ)
	end

	ForwardDiff.hessian(f, log_θ)
end

function sos_log_objective(node::Node, log_θ::AbstractVector, x::AbstractVector,
	                       y::AbstractVector, std_noise::RealOrVec)
	r = similar(y)
	r = _residual!(node.current_phases, log_θ, x, y, r, std_noise)
	return sum(abs2, r)
end

function log_regularizer(log_θ::AbstractVector, mean_θ::RealOrVec, std_θ::RealOrVec)
	p = similar(log_θ)
	sum(abs2, _prior(p, log_θ, mean_θ, std_θ))
end

function hessian_of_kl_objective(phases::AbstractVector, log_θ::AbstractVector, 
	                             x::AbstractVector, y::AbstractVector, 
								 mean_θ::AbstractVector, std_θ::AbstractVector)
    μ = log.(mean_θ)
	function f(log_θ)
		newton_objective(phases, log_θ, x, y, μ, std_θ)
	end

	ForwardDiff.hessian(f, log_θ)
end

function newton_objective(phases::AbstractVector, log_θ::AbstractVector,
	                      x::AbstractVector, y::AbstractVector, 
						  μ::AbstractVector, std_θ::AbstractVector)
	λ = 0
	θ = exp.(log_θ)
	r_θ = reconstruct!(phases, θ, x) # reconstruction of phases, IDEA: pre-allocate result (one for Dual, one for Float)
	r_θ ./= exp(1) # since we are not normalizing the inputs, this rescaling has the effect that kl(α*y, y) has the optimum at α = 1
	kl(r_θ, y) + λ * prior(log_θ, μ, std_θ)
end

function prior(log_θ::AbstractVector, μ::AbstractVector, std_θ::AbstractVector)
	p = zero(eltype(log_θ))
	@inbounds @simd for i in eachindex(log_θ)
		p += (log_θ[i] - μ[i]) / (sqrt(2)*std_θ[i])
	end
	return p
end

function negative_log_marginal_likelihood(Σ⁻¹, y)
	d = length(y)
	return d/2 * log(dot(y, Σ⁻¹, y)) + logdet(Σ⁻¹) # +  + constant x  +
end

marginal_likelihood(x...) = exp(-negative_log_marginal_likelihood(x...))
