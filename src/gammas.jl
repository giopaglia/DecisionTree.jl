
# gammas is a structure holding threshold values for which propositional and modal split labels
#  are on the verge of truth 

# For generic worldTypes, gammas is an n-dim array of dictionaries indicized on the world itself.
#  On the other hand, when the structure of a world is known, its attributes are unrolled as
#  array dimensions; gammas then becomes an (n+k)-dim array,
#  where k is the complexity of the worldType.

const GammaType{NTO, T} =
Union{
	# worldType-agnostic
	AbstractArray{Dict{WorldType,NTuple{NTO, T}}, 3},
	# worldType=ModalLogic.OneWorld
	AbstractArray{T, 4},
	# worldType=ModalLogic.Interval
	AbstractArray{T, 6},
	# worldType=ModalLogic.Interval2D
	AbstractArray{T, 8}
} where {WorldType<:AbstractWorld}

const GammaSliceType{NTO, T} =
Union{
	# worldType-agnostic
	AbstractArray{Dict{WorldType,NTuple{NTO, T}}, 3},
	# worldType=ModalLogic.OneWorld
	AbstractArray{T, 1},
	# worldType=ModalLogic.Interval
	AbstractArray{T, 3},
	# worldType=ModalLogic.Interval2D
	AbstractArray{T, 5}
} where {WorldType<:AbstractWorld}

# TODO test with array-only gammas = Array{T, 4}(undef, 2, n_worlds(world_type(X.ontology), channel_size(X)), n_instances, n_attributes(X))
# TODO try something like gammas = fill(No: Dict{world_type(X.ontology),NTuple{NTO,T}}(), n_instances, n_attributes(X))
# gammas = Vector{Dict{AbstractRelation,Vector{Dict{world_type(X.ontology),NTuple{NTO,T}}}}}(undef, n_attributes(X))		
# TODO maybe use offset-arrays? https://docs.julialang.org/en/v1/devdocs/offset-arrays/

@inline function checkGammasConsistency(gammas, X::OntologicalDataset{T, N, WorldType}, test_operators::AbstractVector{<:TestOperator}, RelationSet::AbstractVector{<:AbstractRelation}) where {T, N, WorldType<:AbstractWorld}
	if !(gammasIsConsistent(gammas, X, length(test_operators), length(RelationSet))) # Note: max(2, ...) because at least RelationId and RelationAll are always present.
		throw("The provided gammas structure is not consistent with the expected dataset, test operators and/or relations!"
			* "\n$(typeof(gammas))"
			* "\n$(eltype(gammas))"
			* "\n$(size(gammas))"
			* "\n$(size(X.domain))"
			* "\n$(WorldType)"
			* "\n$(size(test_operators))"
			* "\n$(X.ontology)"
			* "\n$(size(RelationSet))"
		)
	end
end

# worldType-agnostic gammas
@inline initGammas(worldType::Type{WorldType}, T::Type, channel_size::Tuple, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_features::Integer) where {WorldType<:AbstractWorld} =
	Array{Dict{worldType,NTuple{n_test_operators,T}}, 3}(undef, n_instances, n_relations, n_features)
@inline gammasIsConsistent(gammas, X::OntologicalDataset{T, N, WorldType}, n_test_operators::Integer, n_relations::Integer) where {T, N, WorldType<:AbstractWorld} =
	(typeof(gammas)<:AbstractArray{Dict{WorldType,NTuple{n_test_operators,T}}, 3} && size(gammas) == (n_samples(X), n_relations, n_attributes(X)))
@inline setGamma(gammas::AbstractArray{Dict{WorldType,NTuple{NTO,T}}, 3}, w::WorldType, i_instance::Integer, i_relation::Integer, i_feature::Integer, i_test_operator::Integer, threshold::T) where {WorldType<:AbstractWorld,NTO,T} =
	gammas[i_instance, i_relation, i_feature][w][i_test_operator] = threshold
@inline initGammaSlice(worldType::Type{WorldType}, gammas::AbstractArray{Dict{WorldType,NTuple{NTO,T}}, 3}, i_instance::Integer, i_relation::Integer, i_feature::Integer) where {WorldType<:AbstractWorld,NTO,T} =
	gammas[i_instance, i_relation, i_feature] = Dict{WorldType,NTuple{NTO,T}}()
@inline sliceGammas(worldType::Type{WorldType}, gammas::AbstractArray{Dict{WorldType,NTuple{NTO,T}}, 3}, i_instance::Integer, i_relation::Integer, i_feature::Integer) where {WorldType<:AbstractWorld,NTO,T} =
	gammas[i_instance, i_relation, i_feature]
@inline setGammaSlice(gammaSlice::Dict{WorldType,NTuple{NTO,T}}, w::WorldType, i_test_operator::Integer, threshold::T) where {WorldType<:AbstractWorld,NTO,T} =
	gammaSlice[w][i_test_operator] = threshold
@inline readGammaSlice(gammaSlice::Dict{WorldType,NTuple{NTO,T}}, w::WorldType, i_test_operator::Integer) where {WorldType<:AbstractWorld,NTO,T} =
	gammaSlice[w][i_test_operator]
@inline sliceGammasByInstances(worldType::Type{WorldType}, gammas::AbstractArray{Dict{WorldType,NTuple{NTO,T}}, 3}, inds::AbstractVector{<:Integer}; return_view = false) where {WorldType<:AbstractWorld,NTO, T} =
	if return_view @view gammas[inds,:,:] else gammas[inds,:,:] end
@inline function readGamma(
	gammas          :: AbstractArray{<:AbstractDict{WorldType,NTuple{NTO,T}},3},
	i_test_operator :: Integer,
	w               :: WorldType,
	i_instance      :: Integer,
	i_relation      :: Integer,
	i_feature       :: Integer) where {NTO,T,WorldType<:AbstractWorld}
	gammas[i_instance, i_relation, i_feature][w]
end


# Adimensional case (worldType = ModalLogic.OneWorld)
@inline initGammas(worldType::Type{ModalLogic.OneWorld}, T::Type, channel_size::Tuple, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_features::Integer) =
	Array{T, 4}(undef, n_test_operators, n_instances, n_relations, n_features)
@inline gammasIsConsistent(gammas, X::OntologicalDataset{T, N, ModalLogic.OneWorld}, n_test_operators::Integer, n_relations::Integer) where {T, N}  =
	(typeof(gammas)<:AbstractArray{T, 4} && size(gammas) == (n_test_operators, n_samples(X), n_relations, n_attributes(X)))
@inline setGamma(gammas::AbstractArray{T, 4}, w::ModalLogic.OneWorld, i_instance::Integer, i_relation::Integer, i_feature::Integer, i_test_operator::Integer, threshold::T) where {T} =
	gammas[i_test_operator, i_instance, i_relation, i_feature] = threshold
@inline initGammaSlice(worldType::Type{ModalLogic.OneWorld}, gammas::AbstractArray{T, 4}, i_instance::Integer, i_relation::Integer, i_feature::Integer) where {T} =
	nothing
@inline sliceGammas(worldType::Type{ModalLogic.OneWorld}, gammas::AbstractArray{T, 4}, i_instance::Integer, i_relation::Integer, i_feature::Integer) where {T} =
	@view gammas[:,i_instance, i_relation, i_feature]
@inline setGammaSlice(gammaSlice::AbstractArray{T,1}, w::ModalLogic.OneWorld, i_test_operator::Integer, threshold::T) where {T} =
	gammaSlice[i_test_operator] = threshold
@inline readGammaSlice(gammaSlice::AbstractArray{T,1}, w::ModalLogic.OneWorld, i_test_operator::Integer) where {T} =
	gammaSlice[i_test_operator]
@inline sliceGammasByInstances(worldType::Type{ModalLogic.OneWorld}, gammas::AbstractArray{T, 4}, inds::AbstractVector{<:Integer}; return_view = false) where {T} =
	if return_view @view gammas[:,inds,:,:] else gammas[:,inds,:,:] end
@inline function readGamma(
	gammas          :: AbstractArray{T, 4},
	i_test_operator :: Integer,
	w               :: ModalLogic.OneWorld,
	i_instance      :: Integer,
	i_relation      :: Integer,
	i_feature       :: Integer) where {T}
	gammas[i_test_operator, i_instance, i_relation, i_feature]
end


# 1D Interval case (worldType = ModalLogic.Interval)
@inline initGammas(worldType::Type{ModalLogic.Interval}, T::Type, (X,)::NTuple{1,Integer}, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_features::Integer) =
	Array{T, 6}(undef, X, X+1, n_test_operators, n_instances, n_features, n_relations)
@inline gammasIsConsistent(gammas, X::OntologicalDataset{T, N, ModalLogic.Interval}, n_test_operators::Integer, n_relations::Integer) where {T, N, WorldType<:AbstractWorld} =
	(typeof(gammas)<:AbstractArray{T, 6} && size(gammas) == (channel_size(X)[1], channel_size(X)[1]+1, n_test_operators, n_samples(X), n_attributes(X), n_relations))
@inline setGamma(gammas::AbstractArray{T, 6}, w::ModalLogic.Interval, i_instance::Integer, i_relation::Integer, i_feature::Integer, i_test_operators::Integer, threshold::T) where {T} =
	gammas[w.x, w.y, i_test_operators, i_instance, i_feature, i_relation] = threshold
@inline initGammaSlice(worldType::Type{ModalLogic.Interval}, gammas::AbstractArray{T, 6}, n_instances::Integer, n_relations::Integer, n_features::Integer) where {T} =
	nothing
@inline sliceGammas(worldType::Type{ModalLogic.Interval}, gammas::AbstractArray{T, 6}, i_instance::Integer, i_relation::Integer, i_feature::Integer) where {T} =
	@view gammas[:,:, :, i_instance, i_feature, i_relation]
@inline setGammaSlice(gammaSlice::AbstractArray{T, 3}, w::ModalLogic.Interval, i_test_operators::Integer, threshold::T) where {T} =
	gammaSlice[w.x, w.y, i_test_operators] = threshold
@inline readGammaSlice(gammaSlice::AbstractArray{T, 3}, w::ModalLogic.Interval, i_test_operators::Integer) where {T} =
	gammaSlice[w.x, w.y, i_test_operators]
@inline sliceGammasByInstances(worldType::Type{ModalLogic.Interval}, gammas::AbstractArray{T, 6}, inds::AbstractVector{<:Integer}; return_view = false) where {T} =
	if return_view @view gammas[:,:, :, inds,:,:] else gammas[:,:, :, inds,:,:] end
@inline function readGamma( # TODO add this interface for other cases
	gammas          :: AbstractArray{T, 6},
	i_test_operator :: Integer,
	w               :: ModalLogic.Interval,
	i_instance      :: Integer,
	i_relation      :: Integer,
	i_feature       :: Integer) where {T}
	gammas[w.x, w.y, i_test_operator, i_instance, i_feature, i_relation]
	# (optimized) modal_args = (initCondition = DecisionTree._startWithRelationAll(), useRelationId = true, useRelationAll = false, ontology = Ontology(DecisionTree.ModalLogic.Interval,IARelations), test_operators = DecisionTree.TestOperator[DecisionTree.ModalLogic._TestOpGeq(), DecisionTree.ModalLogic._TestOpLeq()])
	# train size = (5, 226, 40)
	# gammas[i_test_operator, w.x, w.y, i, i_relation, feature]     # 3.981 ms (92645 allocations: 4.01 MiB)
	# @view gammas[:,w.x, w.y, i, i_relation, feature]           # 6.813 ms (119765 allocations: 5.66 MiB)
	# gammas[:,w.x, w.y, i, i_relation, feature]                 # 7.679 ms (119765 allocations: 5.80 MiB)
end


# 2D Interval case (worldType = ModalLogic.Interval2D)
@inline initGammas(worldType::Type{ModalLogic.Interval2D}, T::Type, (X,Y)::NTuple{2,Integer}, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_features::Integer) =
	Array{T, 8}(undef, n_test_operators, X, X+1, Y, Y+1, n_instances, n_relations, n_features)
@inline gammasIsConsistent(gammas, X::OntologicalDataset{T, N, ModalLogic.Interval2D}, n_test_operators::Integer, n_relations::Integer) where {T, N, WorldType<:AbstractWorld} =
	(typeof(gammas)<:AbstractArray{T, 8} && size(gammas) == (n_test_operators, channel_size(X)[1], channel_size(X)[1]+1, channel_size(X)[2], channel_size(X)[2]+1, n_samples(X), n_relations, n_attributes(X)))
@inline setGamma(gammas::AbstractArray{T, 8}, w::ModalLogic.Interval2D, i_instance::Integer, i_relation::Integer, i_feature::Integer, i_test_operators::Integer, threshold::T) where {T} =
	gammas[i_test_operators, w.x.x, w.x.y, w.y.x, w.y.y, i_instance, i_relation, i_feature] = threshold
@inline initGammaSlice(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{T, 8}, n_instances::Integer, n_relations::Integer, n_features::Integer) where {T} =
	nothing
@inline sliceGammas(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{T, 8}, i_instance::Integer, i_relation::Integer, i_feature::Integer) where {T} =
	@view gammas[:, :,:,:,:, i_instance, i_relation, i_feature]
@inline setGammaSlice(gammaSlice::AbstractArray{T, 6}, w::ModalLogic.Interval2D, i_test_operators::Integer, threshold::T) where {T} =
	gammaSlice[i_test_operators, w.x.x, w.x.y, w.y.x, w.y.y] = threshold
@inline readGammaSlice(gammaSlice::AbstractArray{T, 6}, w::ModalLogic.Interval2D, i_test_operators::Integer) where {T} =
	gammaSlice[i_test_operators, w.x.x, w.x.y, w.y.x, w.y.y]
@inline sliceGammasByInstances(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{T, 8}, inds::AbstractVector{<:Integer}; return_view = false) where {T} =
	if return_view @view gammas[:, :,:,:,:, inds,:,:] else gammas[:, :,:,:,:, inds,:,:] end
@inline function readGamma(
	gammas          :: AbstractArray{T, 8},
	i_test_operator :: Integer,
	w               :: ModalLogic.Interval2D,
	i_instance      :: Integer,
	i_relation      :: Integer,
	i_feature       :: Integer) where {T}
	gammas[i_test_operator, w.x.x, w.x.y, w.y.x, w.y.y, i_instance, i_relation, i_feature] # TODO try without view
end

# TODO test which implementation is the best for the 2D case with different memory layout for gammas

# 3x3 spatial window, 12 instances:
# 	Array7 3x4: 90.547 s (1285579691 allocations: 65.67 GiB)
# 	Array5: 105.759 s (1285408103 allocations: 65.70 GiB)
# 	Array7 3x3 con [idx-1]:  113.278 s (1285408102 allocations: 65.69 GiB)
# 	Generic Dict:  100.272 s (1284316309 allocations: 65.64 GiB)
# 	Array8:   100.517 s (1281158366 allocations: 65.49 GiB)
# ---
# using array(undef, ...):	 101.921 s (1285848739 allocations: 65.70 GiB)
# using T[]	100.443 s (1282663890 allocations: 65.69 GiB)

# @inline initGammas(worldType::Type{ModalLogic.Interval2D}, T::Type, (X,Y)::NTuple{2,Integer}, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_features::Integer) =
# 	Array{NTuple{n_test_operators,T}, 5}(undef, div((X*(X+1)),2), div((Y*(Y+1)),2), n_instances, n_relations, n_features)
# @inline setGamma(gammas::AbstractArray{NTuple{NTO,T}, 5}, w::ModalLogic.Interval2D, i_instance::Integer, i_relation::Integer, i_feature::Integer, thresholds::NTuple{NTO,T}) where {NTO,T} =
# 	gammas[w.x.x+div((w.x.y-2)*(w.x.y-1),2), w.y.x+div((w.y.y-2)*(w.y.y-1),2), i_instance, i_relation, i_feature] = thresholds
# @inline initGammaSlice(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{NTuple{NTO,T}, 5}, n_instances::Integer, n_relations::Integer, n_features::Integer) where {NTO,T} =
# 	nothing
# @inline sliceGammas(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{NTuple{NTO,T}, 5}, i_instance::Integer, i_relation::Integer, i_feature::Integer) where {NTO,T} =
# 	@view gammas[:,:, i_instance, i_relation, i_feature]
# @inline setGammaSlice(gammaSlice::AbstractArray{NTuple{NTO,T}, 2}, w::ModalLogic.Interval2D, thresholds::NTuple{NTO,T}) where {NTO,T} =
# 	gammaSlice[w.x.x+div((w.x.y-2)*(w.x.y-1),2), w.y.x+div((w.y.y-2)*(w.y.y-1),2)] = thresholds
# @inline function readGamma(
# 	gammas     :: AbstractArray{NTuple{NTO,T},N},
# 	w          :: ModalLogic.Interval2D,
# 	i, i_relation, feature) where {N,NTO,T}
# 	gammas[w.x.x+div((w.x.y-2)*(w.x.y-1),2), w.y.x+div((w.y.y-2)*(w.y.y-1),2), i, i_relation, feature]
# end

# @inline initGammas(worldType::Type{ModalLogic.Interval2D}, T::Type, (X,Y)::NTuple{2,Integer}, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_features::Integer) =
# 	Array{NTuple{n_test_operators,T}, 7}(undef, X, X, Y, Y, n_instances, n_relations, n_features)
# @inline setGamma(gammas::AbstractArray{NTuple{NTO,T}, 7}, w::ModalLogic.Interval2D, i_instance::Integer, i_relation::Integer, i_feature::Integer, thresholds::NTuple{NTO,T}) where {NTO,T} =
# 	gammas[w.x.x, w.x.y-1, w.y.x, w.y.y-1, i_instance, i_relation, i_feature] = thresholds
# @inline initGammaSlice(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{NTuple{NTO,T}, 7}, n_instances::Integer, n_relations::Integer, n_features::Integer) where {NTO,T} =
# 	nothing
# @inline sliceGammas(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{NTuple{NTO,T}, 7}, i_instance::Integer, i_relation::Integer, i_feature::Integer) where {NTO,T} =
# 	@view gammas[:,:,:,:, i_instance, i_relation, i_feature]
# @inline setGammaSlice(gammaSlice::AbstractArray{NTuple{NTO,T}, 4}, w::ModalLogic.Interval2D, thresholds::NTuple{NTO,T}) where {NTO,T} =
# 	gammaSlice[w.x.x, w.x.y-1, w.y.x, w.y.y-1] = thresholds
# @inline function readGamma(
# 	gammas     :: AbstractArray{NTuple{NTO,T},N},
# 	w          :: ModalLogic.Interval2D,
# 	i, i_relation, feature) where {N,NTO,T}
# 	gammas[w.x.x, w.x.y-1, w.y.x, w.y.y-1, i, i_relation, feature]
# end

# @inline initGammas(worldType::Type{ModalLogic.Interval2D}, T::Type, (X,Y)::NTuple{2,Integer}, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_features::Integer) =
# 	Array{T, 8}(undef, n_test_operators, X, X+1, Y, Y+1, n_instances, n_relations, n_features)
# @inline setGamma(gammas::AbstractArray{T, 8}, w::ModalLogic.Interval2D, i_instance::Integer, i_relation::Integer, i_feature::Integer, i_test_operator::Integer, threshold::T) where {NTO,T} =
# 	gammas[i_test_operator, w.x.x, w.x.y, w.y.x, w.y.y, i_instance, i_relation, i_feature] = threshold
# @inline initGammaSlice(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{T, 8}, n_instances::Integer, n_relations::Integer, n_features::Integer) where {NTO,T} =
# 	nothing
# @inline sliceGammas(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{T, 8}, i_instance::Integer, i_relation::Integer, i_feature::Integer) where {NTO,T} =
# 	@view gammas[:,:,:,:,:, i_instance, i_relation, i_feature]
# @inline setGammaSlice(gammaSlice::AbstractArray{T, 5}, w::ModalLogic.Interval2D, i_test_operator::Integer, threshold::T) where {NTO,T} =
# 	gammaSlice[i_test_operator, w.x.x, w.x.y, w.y.x, w.y.y] = threshold
# @inline function readGamma(
# 	gammas     :: AbstractArray{T,N},
# 	w          :: ModalLogic.Interval2D,
# 	i, i_relation, feature) where {N,T}
# 	@view gammas[:,w.x.x, w.x.y, w.y.x, w.y.y, i, i_relation, feature]
# end

function computeGammas(
		X                  :: OntologicalDataset{T, N, WorldType},
		test_operators     :: AbstractVector{<:TestOperator},
		relationSet        :: Vector{<:AbstractRelation},
		relationId_id      :: Int,
		relation_ids       :: AbstractVector{Int},
	) where {T, N, WorldType<:AbstractWorld}
	
	n_instances = n_samples(X)
	n_features = n_attributes(X)
	n_relations = length(relationSet)

	firstWorld = WorldType(ModalLogic.firstWorld)

	# With sorted test_operators
	# TODO fix
	actual_test_operators = Tuple{Integer,Union{<:TestOperator,Vector{<:TestOperator}}}[]
	already_inserted_test_operators = TestOperator[]
	i_test_operator = 1
	n_actual_operators = 0
	while i_test_operator <= length(test_operators)
		test_operator = test_operators[i_test_operator]
		# println(i_test_operator, test_operators[i_test_operator])
		# @logmsg DTDebug "" test_operator
		# readline()
		if test_operator in already_inserted_test_operators
			# Skip test_operator
		elseif length(test_operators) >= i_test_operator+1 && ModalLogic.dual_test_operator(test_operator) != TestOpNone && ModalLogic.dual_test_operator(test_operator) == test_operators[i_test_operator+1]
			push!(actual_test_operators, (1,ModalLogic.primary_test_operator(test_operator))) # "prim/dual"
			n_actual_operators+=2
			push!(already_inserted_test_operators,test_operators[i_test_operator+1])
		else
			siblings_present = intersect(test_operators,ModalLogic.siblings(test_operator))
			# TODO join batch and prim/dual cases
			if length(siblings_present) > 1
				# TODO test if this is actually better
				push!(actual_test_operators, (2,siblings_present)) # "batch"
				n_actual_operators+=length(siblings_present)
				for sibling in siblings_present
					push!(already_inserted_test_operators,sibling)
				end
			else
				push!(actual_test_operators, (0,test_operator)) # "single"
				n_actual_operators+=1
			end
		end
		i_test_operator+=1
	end
	
	# print(actual_test_operators)
	n_actual_operators = length(test_operators)
	
	# Prepare gammas array
	gammas = initGammas(WorldType, T, channel_size(X), n_actual_operators, n_instances, n_relations, n_features)

	@logmsg DTOverview "Computing gammas... $(typeof(gammas)) $(size(gammas)) $(test_operators)"
	# size(X) WorldType channel_size(X) test_operators n_instances n_relations n_features relationSet relationId_id relation_ids size(gammas)
	# @logmsg DTDebug "Computing gammas..." size(X) WorldType channel_size(X) test_operators n_instances n_relations n_features relationSet relationId_id relation_ids size(gammas)

	# print(actual_test_operators)
	# readline()

	# TODO Note: this only optimizes two generic operators with different polarity, and also works with non-dual pairs of operators. Maybe this function is not needed
	@inline computeModalThresholdWithIdentityLookupDual(gammasId::GammaSliceType{NTO, T}, i_test_operator::Integer, w::WorldType, relation::AbstractRelation, channel::MatricialChannel{T,N}) where {WorldType<:AbstractWorld,NTO,T,N} = begin
		worlds = ModalLogic.enumAccessibles([w], relation, channel)
		extr = (typemin(T),typemax(T))
		for w in worlds
			e = (readGammaSlice(gammasId, w, i_test_operator), readGammaSlice(gammasId, w, i_test_operator+1))
			extr = (min(extr[1],e[1]), max(extr[2],e[2]))
		end
		extr
	end
	@inline computeModalThresholdWithIdentityLookup(gammasId::GammaSliceType{NTO, T}, i_test_operator::Integer, w::WorldType, relation::AbstractRelation, channel::MatricialChannel{T,N}) where {WorldType<:AbstractWorld,NTO,T,N} = begin
		test_operator = test_operators[i_test_operator]
		opt = ModalLogic.opt(test_operator)
		worlds = ModalLogic.enumAccessibles([w], relation, channel)
			# TODO use reduce()
		v = ModalLogic.bottom(test_operator, T) # TODO write with reduce
		for w in worlds
			e = readGammaSlice(gammasId, w, i_test_operator)
			v = opt(v,e)
		end
		v
	end
	@inline computeModalThresholWithIdentityLookupdMany(gammasId::GammaSliceType{NTO, T}, i_test_operators::Vector{<:Integer}, w::WorldType, relation::AbstractRelation, channel::MatricialChannel{T,N}) where {WorldType<:AbstractWorld,NTO,T,N} = begin
		[computeModalThresholdWithIdentityLookup(gammasId, i_test_operator, w, relation, channel) for i_test_operator in i_test_operators]
		# computeModalThresholdWithIdentityLookupDual(gammasId, w, i_test_operator)
	end

	# Avoid using already-computed propositional thresholds
	@inline computeModalThresholdDual(gammasId, test_operator::TestOperator, w::AbstractWorld, relation::AbstractRelation, channel::ModalLogic.MatricialChannel{T,N}) where {T,N} = begin
		ModalLogic.computeModalThresholdDual(test_operator, w, relation, channel)
	end
	@inline computeModalThreshold(gammasId, test_operator::TestOperator, w::AbstractWorld, relation::AbstractRelation, channel::ModalLogic.MatricialChannel{T,N}) where {T,N} = begin
		ModalLogic.computeModalThreshold(test_operator, w, relation, channel)
	end
	@inline computeModalThresholdMany(gammasId, test_operators::Vector{<:TestOperator}, w::AbstractWorld, relation::AbstractRelation, channel::ModalLogic.MatricialChannel{T,N}) where {T,N} = begin
		ModalLogic.computeModalThresholdMany(test_operators, w, relation, channel)
	end

	# @inbounds for feature in 1:n_features
	# TODO maybe swap the two fors on features and instances
	@inbounds Threads.@threads for feature in 1:n_features
		@logmsg DTDebug "Feature $(feature)/$(n_features)"
		if feature == 1 || ((feature+1) % (floor(Int, ((n_features)/5))+1)) == 0
			@logmsg DTOverview "Feature $(feature)/$(n_features)"
		end
		
		# Find the highest/lowest thresholds

		for i in 1:n_instances
			@logmsg DTDebug "Instance $(i)/$(n_instances)"

			# Propositional, local
			channel = ModalLogic.getChannel(X, i, feature) # TODO check that @views actually avoids copying
			initGammaSlice(WorldType, gammas, i, relationId_id, feature)
			# println(channel)
			for w in ModalLogic.enumAccessibles(WorldType[], RelationAll, channel)
				@logmsg DTDetail "World" w

				i_to = 1
				for (mode,test_operator) in actual_test_operators
					if mode == 0
						threshold = ModalLogic.computePropositionalThreshold(test_operator, w, channel)
						setGamma(gammas, w, i, relationId_id, feature, i_to, threshold)
						i_to+=1
					elseif mode == 1
						thresholds = ModalLogic.computePropositionalThresholdDual(test_operator, w, channel)
						setGamma(gammas, w, i, relationId_id, feature, i_to, thresholds[1])
						setGamma(gammas, w, i, relationId_id, feature, i_to+1, thresholds[2])
						i_to+=2
					elseif mode == 2
						thresholds = ModalLogic.computePropositionalThresholdMany(test_operator, w, channel)
						for (i_t,threshold) in enumerate(thresholds)
							setGamma(gammas, w, i, relationId_id, feature, i_to+i_t-1, threshold)
						end
						i_to+=length(thresholds)
					else
						error("Unexpected mode flag for test_operator $(test_operator): $(mode)\n$(test_operators)")
					end
				end
				
				# # thresholds = similar(test_operators, T)
				# i_to=1
				# # println(actual_test_operators)
				# for (mode,test_operator) in actual_test_operators
				# 	if mode == 0
				# 		setGamma(gammas, w, i, relationId_id, feature, i_to, ModalLogic.computePropositionalThreshold(test_operator, w, channel))
				# 		i_to+=1
				# 	elseif mode == 1
				# 		# println("-1")
				# 		# println(ModalLogic.computePropositionalThresholdDual(test_operator, w, channel))
				# 		for t in ModalLogic.computePropositionalThresholdDual(test_operator, w, channel)
				# 			setGamma(gammas, w, i, relationId_id, feature, i_to, t)
				# 			i_to+=1
				# 			# println("-")
				# 		end
				# 	elseif mode == 2
				# 		# println("-2")
				# 		# println(ModalLogic.computePropositionalThresholdMany(test_operator, w, channel))
				# 		for t in ModalLogic.computePropositionalThresholdMany(test_operator, w, channel)
				# 			setGamma(gammas, w, i, relationId_id, feature, i_to, t)
				# 			i_to+=1
				# 			# println("-")
				# 		end
				# 	else
				# 		error("Unexpected mode flag for test_operator $(test_operator): $(mode)\n$(test_operators)")
				# 	end
				# 	# println(w, i_to)
				# end
				# # if i_to != (n_actual_operators+1)
				# # 	error("i_to != (n_actual_operators+1)! $(i_to) != $(n_actual_operators+1)")
				# # end
			end # world

			@views gammasId = sliceGammas(WorldType, gammas, i, relationId_id, feature)
			# Modal
			for relation_id in relation_ids
				relation = relationSet[relation_id]
				initGammaSlice(WorldType, gammas, i, relation_id, feature)
				@logmsg DTDebug "Relation $(relation) (id: $(relation_id))" # "/$(length(relation_ids))"
				# TODO Check if cur_gammas improves performances
				@views cur_gammas = sliceGammas(WorldType, gammas, i, relation_id, feature)
				# For each world w and each relation, compute the thresholds of all v worlds, with w<R>v
				worlds = if relation != RelationAll
						ModalLogic.enumAccessibles(WorldType[], RelationAll, channel)
					else
						[firstWorld]
					end
				for w in worlds

					# TODO use gammasId, TODO gammasId[v]
					i_to = 1
					for (mode,test_operator) in actual_test_operators
						if mode == 0
							# threshold = computeModalThreshold(gammasId, test_operator, w, relation, channel)
							threshold = computeModalThresholdWithIdentityLookup(gammasId, i_to, w, relation, channel)
							setGammaSlice(cur_gammas, w, i_to, threshold)
							i_to+=1
						elseif mode == 1
							# thresholds = computeModalThresholdDual(gammasId, test_operator, w, relation, channel)
							thresholds = computeModalThresholdWithIdentityLookupDual(gammasId, i_to, w, relation, channel)
							setGammaSlice(cur_gammas, w, i_to, thresholds[1])
							setGammaSlice(cur_gammas, w, i_to+1, thresholds[2])
							i_to+=2
						elseif mode == 2
							# thresholds = computeModalThresholdMany(gammasId, test_operator, w, relation, channel)
							thresholds = computeModalThresholWithIdentityLookupdMany(gammasId, collect(i_to:i_to+length(test_operator)-1), w, relation, channel)
							for (i_t,threshold) in enumerate(thresholds)
								setGammaSlice(cur_gammas, w, i_to+i_t-1, threshold)
							end
							i_to+=length(thresholds)
						else
							error("Unexpected mode flag for test_operator $(test_operator): $(mode)\n$(test_operators)")
						end
					end

					# TODO @logmsg DTDetail "World" w relation NTuple{n_actual_operators,T}(thresholds)

					# Quale e' piu' veloce? TODO use gammasId in computePropositionalThresholdDual?
					# @assert (opGeqMaxThresh, opLesMinThresh) == ModalLogic.computePropositionalThresholdDualRepr(ModalLogic.enumAccRepr(w, relation, channel), channel) "computePropositionalThresholdDual different $((opGeqMaxThresh, opLesMinThresh)) $(get_thresholds(w, channel))"

					# setGamma(gammas, w, i, relation_id, feature, NTuple{n_actual_operators,T}(thresholds))
					# setGammaSlice(cur_gammas, w, NTuple{n_actual_operators,T}(thresholds))

					# # TODO use gammasId, TODO gammasId[v]
					# i_to=1
					# for (mode,test_operator) in actual_test_operators
					# 	if mode == 0
					# 		setGammaSlice(cur_gammas, w, i_to, computeModalThreshold(test_operator, gammasId, w, relation, channel))
					# 		i_to+=1
					# 	elseif mode == 1
					# 		for t in computeModalThresholdDual(test_operator, gammasId, w, relation, channel)
					# 			setGammaSlice(cur_gammas, w, i_to, t)
					# 			i_to+=1
					# 		end
					# 	elseif mode == 2
					# 		for t in computeModalThresholdMany(test_operator, gammasId, w, relation, channel)
					# 			setGammaSlice(cur_gammas, w, i_to, t)
					# 			i_to+=1
					# 		end
					# 	else
					# 		error("Unexpected mode flag for test_operator $(test_operator): $(mode)\n$(test_operators)")
					# 	end
					# end
					# if i_to != (n_actual_operators+1)
					# 	error("i_to != (n_actual_operators+1)! $(i_to) != $(n_actual_operators+1)")
					# end 
					# Quale e' piu' veloce? TODO use gammasId in computePropositionalThresholdDual?
					# @assert (opGeqMaxThresh, opLesMinThresh) == ModalLogic.computePropositionalThresholdDualRepr(ModalLogic.enumAccRepr(w, relation, channel), channel) "computePropositionalThresholdDual different $((opGeqMaxThresh, opLesMinThresh)) $(get_thresholds(w, channel))"

					# @logmsg DTDetail "World" w relation

					# setGamma(gammas, w, i, relation_id, feature, Tuple(thresholds))
					# setGammaSlice(cur_gammas, w, Tuple(thresholds))
				end # world
			end # relation
		end # instances
	end # feature
	@logmsg DTDebug "Done computing gammas" # gammas[:,[1,relation_ids...],:]
	gammas
end
