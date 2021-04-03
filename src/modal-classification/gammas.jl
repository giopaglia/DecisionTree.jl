
# gammas is a structure holding threshold values that are on the verge of truth of propositional split formulas.

# For generic worldTypes, gammas is an n-dim array of dictionaries indicized on the world itself.
#  Instead, when the structure of a world is known, its attributes are unrolled as
#  array dimensions; gammas then becomes an (n+k)-dim array,
#  where k is the complexity of the worldType.

# TODO test with array-only gammas = Array{T, 4}(undef, 2, n_worlds(X.ontology.worldType, channel_size(X)), n_instances, n_variables(X))
# TODO try something like gammas = fill(No: Dict{X.ontology.worldType,NTuple{NTO,T}}(), n_instances, n_variables(X))
# gammas = Vector{Dict{ModalLogic.AbstractRelation,Vector{Dict{X.ontology.worldType,NTuple{NTO,T}}}}}(undef, n_variables(X))		
# TODO maybe use offset-arrays? https://docs.julialang.org/en/v1/devdocs/offset-arrays/

# TODO make the test_operators tuple part of the array. ?

# 3x3, 12 istanze in tutto:
# 	Array7 3x4: 90.547 s (1285579691 allocations: 65.67 GiB)
# 	Array5: 105.759 s (1285408103 allocations: 65.70 GiB)
# 	Array7 3x3 con [idx-1]:  113.278 s (1285408102 allocations: 65.69 GiB)
# 	Generic Dict:  100.272 s (1284316309 allocations: 65.64 GiB)
# 	Array8:   100.517 s (1281158366 allocations: 65.49 GiB)
# ---
# using array(undef, ...):	 101.921 s (1285848739 allocations: 65.70 GiB)
# using T[]	100.443 s (1282663890 allocations: 65.69 GiB)

@inline function readGamma(
	gammas     :: AbstractArray{<:AbstractDict{WorldType,NTuple{NTO,T}},3},
	w          :: WorldType,
	i, relation_id, feature) where {NTO,T,WorldType<:AbstractWorld}
	gammas[i, relation_id, feature][w]
end
@inline initGammas(worldType::Type{WorldType}, T::Type, channel_size::Tuple, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_vars::Integer) where {WorldType<:AbstractWorld} =
	Array{Dict{worldType,Array{n_test_operators,T}}, 3}(undef, n_instances, n_relations, n_vars)
@inline setGamma(gammas::Array{Dict{WorldType,NTuple{NTO,T}}, 3}, w::WorldType, i_instances::Integer, i_relations::Integer, i_vars::Integer, i_test_operator::Integer, threshold::T) where {WorldType<:AbstractWorld,NTO,T} =
	gammas[i_instances, i_relations, i_vars][w][i_test_operator] = threshold
@inline initGammaSlice(worldType::Type{WorldType}, gammas::Array{Dict{WorldType,NTuple{NTO,T}}, 3}, i_instances::Integer, i_relations::Integer, i_vars::Integer) where {WorldType<:AbstractWorld,NTO,T} =
	gammas[i_instances, i_relations, i_vars] = Dict{WorldType,NTuple{NTO,T}}()
@inline sliceGammas(worldType::Type{WorldType}, gammas::Array{Dict{WorldType,NTuple{NTO,T}}, 3}, i_instances::Integer, i_relations::Integer, i_vars::Integer) where {WorldType<:AbstractWorld,NTO,T} =
	gammas[i_instances, i_relations, i_vars]
@inline setGammaSlice(gammasSlice::Dict{WorldType,NTuple{NTO,T}}, w::WorldType, i_test_operator::Integer, threshold::T) where {WorldType<:AbstractWorld,NTO,T} =
	gammasSlice[w][i_test_operator] = threshold



@inline initGammas(worldType::Type{ModalLogic.Interval}, T::Type, (X,)::NTuple{1,Integer}, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_vars::Integer) =
	Array{NTuple{n_test_operators,T}, 5}(undef, X, X+1, n_instances, n_relations, n_vars)
@inline setGamma(gammas::Array{NTuple{NTO,T}, 5}, w::ModalLogic.Interval, i_instances::Integer, i_relations::Integer, i_vars::Integer, thresholds::NTuple{NTO,T}) where {NTO,T} =
	gammas[w.x, w.y, i_instances, i_relations, i_vars] = thresholds
@inline initGammaSlice(worldType::Type{ModalLogic.Interval}, gammas::Array{NTuple{NTO,T}, 5}, n_instances::Integer, n_relations::Integer, n_vars::Integer) where {NTO,T} =
	nothing
@inline sliceGammas(worldType::Type{ModalLogic.Interval}, gammas::Array{NTuple{NTO,T}, 5}, i_instances::Integer, i_relations::Integer, i_vars::Integer) where {NTO,T} =
	@view gammas[:,:, i_instances, i_relations, i_vars]
@inline setGammaSlice(gammasSlice::AbstractArray{NTuple{NTO,T}, 2}, w::ModalLogic.Interval, thresholds::NTuple{NTO,T}) where {NTO,T} =
	gammasSlice[w.x, w.y] = thresholds
@inline function readGamma(
	gammas     :: AbstractArray{NTuple{NTO,T},N},
	w          :: ModalLogic.Interval,
	i, relation_id, feature) where {N,NTO,T}
	gammas[w.x, w.y, i, relation_id, feature]
end


# TODO
# @inline function readGamma(
# 	gammas     :: AbstractArray{NTuple{NTO,T},N},
# 	w          :: ModalLogic.Interval,
# 	i, relation_id, feature) where {N,NTO,T}
# 	gammas[w.x, w.y, i, relation_id, feature]
# end

# @inline initGammas(worldType::Type{ModalLogic.Interval2D}, T::Type, (X,Y)::NTuple{2,Integer}, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_vars::Integer) =
# 	Array{NTuple{n_test_operators,T}, 5}(undef, div((X*(X+1)),2), div((Y*(Y+1)),2), n_instances, n_relations, n_vars)
# @inline setGamma(gammas::Array{NTuple{NTO,T}, 5}, w::ModalLogic.Interval2D, i_instances::Integer, i_relations::Integer, i_vars::Integer, thresholds::NTuple{NTO,T}) where {NTO,T} =
# 	gammas[w.x.x+div((w.x.y-2)*(w.x.y-1),2), w.y.x+div((w.y.y-2)*(w.y.y-1),2), i_instances, i_relations, i_vars] = thresholds
# @inline initGammaSlice(worldType::Type{ModalLogic.Interval2D}, gammas::Array{NTuple{NTO,T}, 5}, n_instances::Integer, n_relations::Integer, n_vars::Integer) where {NTO,T} =
# 	nothing
# @inline sliceGammas(worldType::Type{ModalLogic.Interval2D}, gammas::Array{NTuple{NTO,T}, 5}, i_instances::Integer, i_relations::Integer, i_vars::Integer) where {NTO,T} =
# 	@view gammas[:,:, i_instances, i_relations, i_vars]
# @inline setGammaSlice(gammasSlice::AbstractArray{NTuple{NTO,T}, 2}, w::ModalLogic.Interval2D, thresholds::NTuple{NTO,T}) where {NTO,T} =
# 	gammasSlice[w.x.x+div((w.x.y-2)*(w.x.y-1),2), w.y.x+div((w.y.y-2)*(w.y.y-1),2)] = thresholds
# @inline function readGamma(
# 	gammas     :: AbstractArray{NTuple{NTO,T},N},
# 	w          :: ModalLogic.Interval2D,
# 	i, relation_id, feature) where {N,NTO,T}
# 	gammas[w.x.x+div((w.x.y-2)*(w.x.y-1),2), w.y.x+div((w.y.y-2)*(w.y.y-1),2), i, relation_id, feature]
# end

# @inline initGammas(worldType::Type{ModalLogic.Interval2D}, T::Type, (X,Y)::NTuple{2,Integer}, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_vars::Integer) =
# 	Array{NTuple{n_test_operators,T}, 7}(undef, X, X, Y, Y, n_instances, n_relations, n_vars)
# @inline setGamma(gammas::Array{NTuple{NTO,T}, 7}, w::ModalLogic.Interval2D, i_instances::Integer, i_relations::Integer, i_vars::Integer, thresholds::NTuple{NTO,T}) where {NTO,T} =
# 	gammas[w.x.x, w.x.y-1, w.y.x, w.y.y-1, i_instances, i_relations, i_vars] = thresholds
# @inline initGammaSlice(worldType::Type{ModalLogic.Interval2D}, gammas::Array{NTuple{NTO,T}, 7}, n_instances::Integer, n_relations::Integer, n_vars::Integer) where {NTO,T} =
# 	nothing
# @inline sliceGammas(worldType::Type{ModalLogic.Interval2D}, gammas::Array{NTuple{NTO,T}, 7}, i_instances::Integer, i_relations::Integer, i_vars::Integer) where {NTO,T} =
# 	@view gammas[:,:,:,:, i_instances, i_relations, i_vars]
# @inline setGammaSlice(gammasSlice::AbstractArray{NTuple{NTO,T}, 4}, w::ModalLogic.Interval2D, thresholds::NTuple{NTO,T}) where {NTO,T} =
# 	gammasSlice[w.x.x, w.x.y-1, w.y.x, w.y.y-1] = thresholds
# @inline function readGamma(
# 	gammas     :: AbstractArray{NTuple{NTO,T},N},
# 	w          :: ModalLogic.Interval2D,
# 	i, relation_id, feature) where {N,NTO,T}
# 	gammas[w.x.x, w.x.y-1, w.y.x, w.y.y-1, i, relation_id, feature]
# end

@inline initGammas(worldType::Type{ModalLogic.Interval2D}, T::Type, (X,Y)::NTuple{2,Integer}, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_vars::Integer) =
	Array{NTuple{n_test_operators,T}, 7}(undef, X, X+1, Y, Y+1, n_instances, n_relations, n_vars)
@inline setGamma(gammas::Array{NTuple{NTO,T}, 7}, w::ModalLogic.Interval2D, i_instances::Integer, i_relations::Integer, i_vars::Integer, thresholds::NTuple{NTO,T}) where {NTO,T} =
	gammas[w.x.x, w.x.y, w.y.x, w.y.y, i_instances, i_relations, i_vars] = thresholds
@inline initGammaSlice(worldType::Type{ModalLogic.Interval2D}, gammas::Array{NTuple{NTO,T}, 7}, n_instances::Integer, n_relations::Integer, n_vars::Integer) where {NTO,T} =
	nothing
@inline sliceGammas(worldType::Type{ModalLogic.Interval2D}, gammas::Array{NTuple{NTO,T}, 7}, i_instances::Integer, i_relations::Integer, i_vars::Integer) where {NTO,T} =
	@view gammas[:,:,:,:, i_instances, i_relations, i_vars]
@inline setGammaSlice(gammasSlice::AbstractArray{NTuple{NTO,T}, 4}, w::ModalLogic.Interval2D, thresholds::NTuple{NTO,T}) where {NTO,T} =
	gammasSlice[w.x.x, w.x.y, w.y.x, w.y.y] = thresholds
@inline function readGamma(
	gammas     :: AbstractArray{NTuple{NTO,T},N},
	w          :: ModalLogic.Interval2D,
	i, relation_id, feature) where {N,NTO,T}
	gammas[w.x.x, w.x.y, w.y.x, w.y.y, i, relation_id, feature]
end

# @inline initGammas(worldType::Type{ModalLogic.Interval2D}, T::Type, (X,Y)::NTuple{2,Integer}, n_test_operators::Integer, n_instances::Integer, n_relations::Integer, n_vars::Integer) =
# 	Array{T, 8}(undef, n_test_operators, X, X+1, Y, Y+1, n_instances, n_relations, n_vars)
# @inline setGamma(gammas::AbstractArray{T, 8}, w::ModalLogic.Interval2D, i_instances::Integer, i_relations::Integer, i_vars::Integer, i_test_operator::Integer, threshold::T) where {NTO,T} =
# 	gammas[i_test_operator, w.x.x, w.x.y, w.y.x, w.y.y, i_instances, i_relations, i_vars] = threshold
# @inline initGammaSlice(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{T, 8}, n_instances::Integer, n_relations::Integer, n_vars::Integer) where {NTO,T} =
# 	nothing
# @inline sliceGammas(worldType::Type{ModalLogic.Interval2D}, gammas::AbstractArray{T, 8}, i_instances::Integer, i_relations::Integer, i_vars::Integer) where {NTO,T} =
# 	@view gammas[:,:,:,:,:, i_instances, i_relations, i_vars]
# @inline setGammaSlice(gammasSlice::AbstractArray{T, 5}, w::ModalLogic.Interval2D, i_test_operator::Integer, threshold::T) where {NTO,T} =
# 	gammasSlice[i_test_operator, w.x.x, w.x.y, w.y.x, w.y.y] = threshold
# @inline function readGamma(
# 	gammas     :: AbstractArray{T,N},
# 	w          :: ModalLogic.Interval2D,
# 	i, relation_id, feature) where {N,T}
# 	@view gammas[:,w.x.x, w.x.y, w.y.x, w.y.y, i, relation_id, feature]
# end

function computeGammas(
		X                  :: OntologicalDataset{T, N},
		worldType          :: Type{WorldType},
		test_operators     :: AbstractVector{<:ModalLogic.TestOperator},
		relationSet        :: Vector{<:ModalLogic.AbstractRelation},
		relationId_id      :: Int,
		relation_ids       :: AbstractVector{Int},
	) where {T, N, WorldType<:AbstractWorld}
	
	n_instances = n_samples(X)
	n_vars = n_variables(X)
	n_relations = length(relationSet)

	firstWorld = worldType(ModalLogic.firstWorld)

	# With sorted test_operators
	# TODO fix
	actual_test_operators = Tuple{Integer,Union{<:ModalLogic.TestOperator,Vector{<:ModalLogic.TestOperator}}}[]
	already_inserted_test_operators = ModalLogic.TestOperator[]
	i_test_operator = 1
	n_actual_operators = 0
	while i_test_operator <= length(test_operators)
		test_operator = test_operators[i_test_operator]
		# println(i_test_operator, test_operators[i_test_operator])
		# @logmsg DTDebug "" test_operator
		# readline()
		if test_operator in already_inserted_test_operators
			# Skip test_operator
		elseif length(test_operators) >= i_test_operator+1 && ModalLogic.dual_test_operator(test_operator) != ModalLogic.TestOpNone && ModalLogic.dual_test_operator(test_operator) == test_operators[i_test_operator+1]
			push!(actual_test_operators, (1,ModalLogic.primary_test_operator(test_operator))) # "prim/dual"
			n_actual_operators+=1
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
				n_actual_operators+=2
			end
		end
		i_test_operator+=1
	end
	
	# print(actual_test_operators)
	n_actual_operators = length(test_operators)

	# Prepare gammas array
	gammas = initGammas(worldType, T, channel_size(X), n_actual_operators, n_instances, n_relations, n_vars)

	@logmsg DTOverview "Computing gammas... $(typeof(gammas)) $(size(gammas)) $(test_operators)"
	# size(X) worldType channel_size(X) test_operators n_instances n_relations n_vars relationSet relationId_id relation_ids size(gammas)
	# @logmsg DTDebug "Computing gammas..." size(X) worldType channel_size(X) test_operators n_instances n_relations n_vars relationSet relationId_id relation_ids size(gammas)

	# print(actual_test_operators)
	# readline()

	@inline WExtremaModal(test_operator::ModalLogic.TestOperator, gammasId, w::AbstractWorld, relation::AbstractRelation, channel::ModalLogic.MatricialChannel{T,N}) where {T,N} = begin
		# TODO use gammasId[w.x.x, w.x.y, w.y.x, w.y.y]...?
		ModalLogic.WExtremaModal(test_operator, w, relation, channel)

		# TODO fix this
		# accrepr = ModalLogic.enumAccRepr(test_operator, w, relation, channel)

		# # TODO use 
		# # accrepr::Tuple{Bool,AbstractWorldSet{<:AbstractWorld}}
		# inverted, representatives = accrepr
		# opGeqMaxThresh, opLesMinThresh = typemin(T), typemax(T)
		# for w in representatives
		# 	(_wmin, _wmax) = ModalLogic.WExtrema(test_operator, w, channel)
		# 	if inverted
		# 		(_wmax, _wmin) = (_wmin, _wmax)
		# 	end
		# 	opGeqMaxThresh = max(opGeqMaxThresh, _wmin)
		# 	opLesMinThresh = min(opLesMinThresh, _wmax)
		# end
		# return (opGeqMaxThresh, opLesMinThresh)
	end

	@inline WExtremeModal(test_operator::ModalLogic.TestOperator, gammasId, w::AbstractWorld, relation::AbstractRelation, channel::ModalLogic.MatricialChannel{T,N}) where {T,N} = begin
		ModalLogic.WExtremeModal(test_operator, w, relation, channel)
	# 	# TODO fix this
	# 	accrepr = ModalLogic.enumAccRepr(test_operator, w, relation, channel)
		
	# 	# TODO use gammasId[w.x.x, w.x.y, w.y.x, w.y.y]
	# 	# accrepr::Tuple{Bool,AbstractWorldSet{<:AbstractWorld}}
	# 	inverted, representatives = accrepr
	# 	TODO inverted...
	# 	(opExtremeThresh, optimizer) = if ModalLogic.polarity(test_operator)
	# 			typemin(T), max
	# 		else
	# 			typemax(T), min
	# 		end
	# 	for w in representatives
	# 		_wextreme = ModalLogic.WExtreme(test_operator, w, channel)
	# 		opExtremeThresh = optimizer(opExtremeThresh, _wextreme)
	# 	end
	# 	return opExtremeThresh
	end

	@inline WExtremeModalMany(test_operators::Vector{<:ModalLogic.TestOperator}, gammasId, w::AbstractWorld, relation::AbstractRelation, channel::ModalLogic.MatricialChannel{T,N}) where {T,N} = begin
		# TODO use gammasId[w.x.x, w.x.y, w.y.x, w.y.y]...?
		ModalLogic.WExtremeModalMany(test_operators, w, relation, channel)
	end

	# @inbounds for feature in 1:n_vars
	@inbounds Threads.@threads for feature in 1:n_vars
		@logmsg DTDebug "Feature $(feature)/$(n_vars)"
		if feature == 1 || ((feature+1) % (floor(Int, ((n_vars)/5))+1)) == 0
			@logmsg DTOverview "Feature $(feature)/$(n_vars)"
		end
		
		# Find the highest/lowest thresholds

		for i in 1:n_instances
			@logmsg DTDebug "Instance $(i)/$(n_instances)"

			# Propositional, local
			channel = ModalLogic.getFeature(X.domain, i, feature) # TODO check that @views actually avoids copying
			initGammaSlice(worldType, gammas, i, relationId_id, feature)
			# println(channel)
			for w in ModalLogic.enumAcc(worldType[], ModalLogic.RelationAll, channel)
				@logmsg DTDetail "World" w
				thresholds  = T[]
				for (mode,test_operator) in actual_test_operators
					thresholds = if mode == 0
						[thresholds..., ModalLogic.WExtreme(test_operator, w, channel)]
					elseif mode == 1
						[thresholds..., ModalLogic.WExtrema(test_operator, w, channel)...]
					elseif mode == 2
						[thresholds..., ModalLogic.WExtremeMany(test_operator, w, channel)...]
					else
						error("Unexpected mode flag for test_operator $(test_operator): $(mode)\n$(test_operators)")
					end
				end
				setGamma(gammas, w, i, relationId_id, feature, Tuple(thresholds))

				# # thresholds = similar(test_operators, T)
				# i_to=1
				# # println(actual_test_operators)
				# for (mode,test_operator) in actual_test_operators
				# 	if mode == 0
				# 		setGamma(gammas, w, i, relationId_id, feature, i_to, ModalLogic.WExtreme(test_operator, w, channel))
				# 		i_to+=1
				# 	elseif mode == 1
				# 		# println("-1")
				# 		# println(ModalLogic.WExtrema(test_operator, w, channel))
				# 		for t in ModalLogic.WExtrema(test_operator, w, channel)
				# 			setGamma(gammas, w, i, relationId_id, feature, i_to, t)
				# 			i_to+=1
				# 			# println("-")
				# 		end
				# 	elseif mode == 2
				# 		# println("-2")
				# 		# println(ModalLogic.WExtremeMany(test_operator, w, channel))
				# 		for t in ModalLogic.WExtremeMany(test_operator, w, channel)
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

			@views gammasId = sliceGammas(worldType, gammas, i, relationId_id, feature)
			# Modal
			for relation_id in relation_ids
				relation = relationSet[relation_id]
				initGammaSlice(worldType, gammas, i, relation_id, feature)
				@logmsg DTDebug "Relation $(relation) (id: $(relation_id))" # "/$(length(relation_ids))"
				# TOD Check if cur_gammas improves performances
				@views cur_gammas = sliceGammas(worldType, gammas, i, relation_id, feature)
				# For each world w and each relation, compute the thresholds of all v worlds, with w<R>v
				worlds = if relation != ModalLogic.RelationAll
						ModalLogic.enumAcc(worldType[], ModalLogic.RelationAll, channel)
					else
						[firstWorld]
					end
				for w in worlds

					thresholds  = T[]

					# TODO use gammasId, TODO gammasId[v]
					for (mode,test_operator) in actual_test_operators
						thresholds = if mode == 0
							[thresholds..., WExtremeModal(test_operator, gammasId, w, relation, channel)]
						elseif mode == 1
							[thresholds..., WExtremaModal(test_operator, gammasId, w, relation, channel)...]
						elseif mode == 2
							[thresholds..., WExtremeModalMany(test_operator, gammasId, w, relation, channel) ...]
						else
							error("Unexpected mode flag for test_operator $(test_operator): $(mode)\n$(test_operators)")
						end
					end
					# Quale e' piu' veloce? TODO use gammasId in Wextrema?
					# @assert (opGeqMaxThresh, opLesMinThresh) == ModalLogic.WExtremaRepr(ModalLogic.enumAccRepr(w, relation, channel), channel) "Wextrema different $((opGeqMaxThresh, opLesMinThresh)) $(get_thresholds(w, channel))"

					@logmsg DTDetail "World" w relation Tuple(thresholds)

					# setGamma(gammas, w, i, relation_id, feature, Tuple(thresholds))
					setGammaSlice(cur_gammas, w, Tuple(thresholds))

					# # TODO use gammasId, TODO gammasId[v]
					# i_to=1
					# for (mode,test_operator) in actual_test_operators
					# 	if mode == 0
					# 		setGammaSlice(cur_gammas, w, i_to, WExtremeModal(test_operator, gammasId, w, relation, channel))
					# 		i_to+=1
					# 	elseif mode == 1
					# 		for t in WExtremaModal(test_operator, gammasId, w, relation, channel)
					# 			setGammaSlice(cur_gammas, w, i_to, t)
					# 			i_to+=1
					# 		end
					# 	elseif mode == 2
					# 		for t in WExtremeModalMany(test_operator, gammasId, w, relation, channel)
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
					# Quale e' piu' veloce? TODO use gammasId in Wextrema?
					# @assert (opGeqMaxThresh, opLesMinThresh) == ModalLogic.WExtremaRepr(ModalLogic.enumAccRepr(w, relation, channel), channel) "Wextrema different $((opGeqMaxThresh, opLesMinThresh)) $(get_thresholds(w, channel))"

					# @logmsg DTDetail "World" w relation

					# setGamma(gammas, w, i, relation_id, feature, Tuple(thresholds))
					# setGammaSlice(cur_gammas, w, Tuple(thresholds))
				end # world
			end # relation

			# w = firstWorld
			# println(gammas[w.x.x, w.x.y, w.y.x, w.y.y, i,2,feature])
			# readline()

		end # instances
	end # feature
	@logmsg DTDebug "Done computing gammas" # gammas[:,[1,relation_ids...],:]
	gammas
end