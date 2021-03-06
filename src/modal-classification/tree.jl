# The code in this file is a small port from scikit-learn's and numpy's
# library which is distributed under the 3-Clause BSD license.
# The rest of DecisionTree.jl is released under the MIT license.

# written by Poom Chiarawongse <eight1911@gmail.com>

module treeclassifier
	
	export fit, optimize_tree_parameters!, computeGammas

	using ..ModalLogic
	using ..DecisionTree
	using DecisionTree.util
	using Logging: @logmsg
	import Random
	import StatsBase

	mutable struct NodeMeta{S<:Real,U}
		region           :: UnitRange{Int}                   # a slice of the samples used to decide the split of the node
		depth            :: Int
		modal_depth      :: Int
		# worlds      :: AbstractVector{WorldSet{W}}         # current set of worlds for each training instance
		purity           :: U                                # purity grade attained at training time
		label            :: Label                            # most likely label
		is_leaf          :: Bool                             # whether this is a leaf node, or a split one
		# split node-only properties
		split_at         :: Int                              # index of samples
		l                :: NodeMeta{S,U}                    # left child
		r                :: NodeMeta{S,U}                    # right child
		modality         :: R where R<:AbstractRelation      # modal operator (e.g. RelationId for the propositional case)
		attribute          :: Int                              # attribute used for splitting
		test_operator    :: TestOperator          # test_operator (e.g. <=)
		threshold        :: S                                # threshold value
		function NodeMeta{S,U}(
				region      :: UnitRange{Int},
				depth       :: Int,
				modal_depth :: Int
				) where {S<:Real,U}
			node = new{S,U}()
			node.region = region
			node.depth = depth
			node.modal_depth = modal_depth
			node.purity = U(NaN)
			node.is_leaf = false
			node
		end
	end

	struct Tree{S, T}
		root           :: NodeMeta{S,Float64}
		list           :: Vector{T}
		labels         :: Vector{Label}
		initCondition  :: DecisionTree._initCondition
	end

	# Find an optimal local split satisfying the given constraints
	#  (e.g. max_depth, min_samples_leaf, etc.)
	# TODO move this function inside the caller function, and get rid of all parameters
	function _split!(
							X                   :: OntologicalDataset{T, N, WorldType}, # the ontological dataset
							Y                   :: AbstractVector{Label},    # the label array
							W                   :: AbstractVector{U},        # the weight vector
							S                   :: AbstractVector{WorldSet{WorldType}}, # the vector of current worlds

							loss_function       :: Function,
							node                :: NodeMeta{T,<:AbstractFloat}, # the node to split
							n_subfeatures       :: Int,                      # number of features to use to split
							max_depth           :: Int,                      # the maximum depth of the resultant tree
							min_samples_leaf    :: Int,                      # the minimum number of samples each leaf needs to have
							min_loss_at_leaf    :: AbstractFloat,            # maximum purity allowed on a leaf
							min_purity_increase :: AbstractFloat,            # minimum purity increase needed for a split
							n_subrelations      :: Function,
							test_operators      :: AbstractVector{<:TestOperator},
							
							indX                :: AbstractVector{Int},      # an array of sample indices (we split using samples in indX[node.region])
							
							# The six arrays below are given for optimization purposes
							
							nc                  :: AbstractVector{U},   # nc maintains a dictionary of all labels in the samples
							ncl                 :: AbstractVector{U},   # ncl maintains the counts of labels on the left
							ncr                 :: AbstractVector{U},   # ncr maintains the counts of labels on the right
							
							# Xf                  :: MatricialUniDataset{T, M}, # Note that X and Xf are not used when using Gammas
							Yf                  :: AbstractVector{Label},
							Wf                  :: AbstractVector{U},
							Sf                  :: AbstractVector{WorldSet{WorldType}},
							gammas              :: GammaType{NTO, T},
							# TODO Ef                  :: AbstractArray{T},
							
							relationSet         :: AbstractVector{<:AbstractRelation},
							relation_ids        :: AbstractVector{Int},
							featureSet          :: AbstractVector{<:FeatureType},
							rng                 :: Random.AbstractRNG,
							) where {WorldType<:AbstractWorld, T, U, N, M, NTO, L}

		# Region of indX to use to perform the split
		region = node.region
		n_instances = length(region)
		r_start = region.start - 1

		# Class counts
		nc[:] .= zero(U)
		@simd for i in region
			@inbounds nc[Y[indX[i]]] += W[indX[i]]
		end
		nt = sum(nc)
		node.purity = loss_function(nc, nt)
		node.label = argmax(nc) # Assign the most likely label before the split

		@logmsg DTDebug "_split!(...) " n_instances region nt

		# Preemptive leaf conditions
		if (
			# If all the instances belong to the same class, make this a leaf
			 (nc[node.label]       == nt)
			# No binary split can honor min_samples_leaf if there aren't as many as
			#  min_samples_leaf*2 instances in the first place
			 || (min_samples_leaf * 2 >  n_instances)
			# If the node is pure enough, avoid splitting # TODO rename purity to loss
			 || (node.purity          <= min_loss_at_leaf)
			# Honor maximum depth constraint
			 || (max_depth            <= node.depth))
			node.is_leaf = true
			@logmsg DTDetail "leaf created: " (min_samples_leaf * 2 >  n_instances) (nc[node.label] == nt) (node.purity  <= min_loss_at_leaf) (max_depth <= node.depth)
			return
		end

		# Gather all values needed for the current set of instances
		# TODO also slice gammas in gammasf?
		@simd for i in 1:n_instances
			Yf[i] = Y[indX[i + r_start]]
			Wf[i] = W[indX[i + r_start]]
			Sf[i] = S[indX[i + r_start]]
		end

		# Optimization-tracking variables
		best_purity__nt = typemin(U)
		best_relation = RelationNone
		best_feature = -1
		best_test_operator = TestOpNone
		best_threshold = typemin(U)

		# TODO these are just for checking the consistency of gamma-optimizations
		best_nl = -1
		# TODO bring back best_unsatisfied = []
		
		# array of indices of features
		# Note: using "sample" function instead of "randperm" allows to insert weights for features which may be wanted in the future 
		features_inds = StatsBase.sample(rng, Vector(1:n_attributes(X)), n_subfeatures, replace = false)

		# use a subset of relations
		# TODO does this go inside the for on the features?
		relations_ids = StatsBase.sample(rng, relation_ids, Int(n_subrelations(length(relation_ids))), replace = false)

		#####################
		## Find best split ##
		#####################
		## Test all conditions
		# For each relational operator
		for relation_id in relations_ids
			relation = relationSet[relation_id]
			@logmsg DTDebug "Testing relation $(relation) (id: $(relation_id))..." # "/$(length(relation_ids))"

			# For each feature
			@inbounds for feature in features_inds
				@logmsg DTDebug "Testing feature $(feature)/$(n_subfeatures)..."
				relation_real = featureSet[feature]

				thresholds = Array{T,2}(undef, length(test_operators), n_instances)
				for (i_test_operator,test_operator) in enumerate(test_operators)
					@views cur_thr = thresholds[i_test_operator,:]
					fill!(cur_thr, ModalLogic.bottom(test_operator, T))
				end

				@logmsg DTDebug "thresholds: " thresholds

				# TODO optimize this!!
				firstWorld = WorldType(ModalLogic.firstWorld)
				for i in 1:n_instances
					@logmsg DTDetail " Instance $(i)/$(n_instances)" indX[i + r_start]
					worlds = if (relation != RelationAll)
							Sf[i]
						else
							[firstWorld]
						end
					# TODO maybe read the specific value of gammas referred to the test_operator?
					# cur_gammas = DecisionTree.readGamma(gammas, w, indX[i + r_start], relation_id, feature)
					# @logmsg DTDetail " cur_gammas" w cur_gammas
					# TODO try using reduce for each operator instead.
					for (i_test_operator,test_operator) in enumerate(test_operators) # TODO use correct indexing for test_operators
						for w in worlds
							# thresholds[i_test_operator,i] = ModalLogic.opt(test_operator)(thresholds[i_test_operator,i], cur_gammas[i_test_operator])
							gamma = DecisionTree.readGamma(gammas, i_test_operator, w, indX[i + r_start], relation_id, feature)
							thresholds[i_test_operator,i] = ModalLogic.opt(test_operator)(thresholds[i_test_operator,i], gamma)
						end
					end
				end

				# TODO sort this and optimize?
				# TODO no need to do union!! Just use opGeqMaxThresh for one and opLesMinThresh for the other...
				# Obtain the list of reasonable thresholds
				
				# thresholdDomain = setdiff(union(Set(opGeqMaxThresh),Set(opLesMinThresh)),Set([typemin(T), typemax(T)]))

				# @logmsg DTDebug "Thresholds computed: " thresholds
				# readline()

				# Look for the correct test operator
				for (i_test_operator,test_operator) in enumerate(test_operators)
					thresholdArr = @views thresholds[i_test_operator,:]
					thresholdDomain = setdiff(Set(thresholdArr),Set([typemin(T), typemax(T)]))
					# Look for thresholdArr 'a' for the propositions like "feature >= a"
					for threshold in thresholdDomain
						@logmsg DTDebug " Testing condition: $(display_modal_test(relation, test_operator, relation_real, threshold))"
						# Re-initialize right class counts
						nr = zero(U)
						ncr[:] .= zero(U)
						# unsatisfied = fill(1, n_instances)
						for i in 1:n_instances
							# @logmsg DTDetail " instance $i/$n_instances ExtremeThresh ($(opGeqMaxThresh[i])/$(opLesMinThresh[i]))"
							satisfied = ModalLogic.evaluateThreshCondition(test_operator, threshold, thresholdArr[i])
							
							if !satisfied
								@logmsg DTDetail "NO"
								nr += Wf[i]
								ncr[Yf[i]] += Wf[i]
							else
								# unsatisfied[i] = 0
								@logmsg DTDetail "YES"
							end
						end

						# Calculate left class counts
						@simd for lab in 1:length(nc) # TODO something like @simd ncl .= nc - ncr instead
							ncl[lab] = nc[lab] - ncr[lab]
						end
						nl = nt - nr
						@logmsg DTDebug "  (n_left,n_right) = ($nl,$nr)"

						# Honor min_samples_leaf
						if nl >= min_samples_leaf && (n_instances - nl) >= min_samples_leaf
							purity__nt = -(nl * loss_function(ncl, nl) +
								      	 nr * loss_function(ncr, nr))
							if purity__nt > best_purity__nt && !isapprox(purity__nt, best_purity__nt)
								best_purity__nt     = purity__nt
								best_relation       = relation
								best_feature        = feature
								best_test_operator  = test_operator
								best_threshold      = threshold
								# TODO just for checking the consistency of optimizations
								best_nl             = nl
								# TODO bring back best_unsatisfied    = unsatisfied
								@logmsg DTDetail "  Found new optimum: " (best_purity__nt/nt) best_relation best_feature best_test_operator best_threshold
							end
						end
					end # for threshold
				end # for test_operator
			end # for relation
		end # for feature

		# @logmsg DTOverview "purity increase" best_purity__nt/nt node.purity (best_purity__nt/nt + node.purity) (best_purity__nt/nt - node.purity)
		# If the best split is good, partition and split accordingly
		@inbounds if (best_purity__nt == typemin(U)
									|| (best_purity__nt/nt + node.purity <= min_purity_increase))
			@logmsg DTDebug " Leaf" best_purity__nt min_purity_increase (best_purity__nt/nt) node.purity ((best_purity__nt/nt) + node.purity)
			node.is_leaf = true
			return
		else
			best_purity = best_purity__nt/nt

			# split the samples into two parts:
			# - ones that are > threshold
			# - ones that are <= threshold

			node.purity         = best_purity
			node.modality       = best_relation
			node.attribute      = best_feature
			node.test_operator  = best_test_operator
			# TODO the selected threshold should actually be the result of a loss interpolation around best_threshold
			node.threshold      = best_threshold
			
			# Compute new world sets (= make a modal step)

			# TODO instead of using memory, here, just use two opposite indices and perform substitutions. indj = n_instances
			unsatisfied_flags = fill(1, n_instances)
			for i in 1:n_instances
				channel = ModalLogic.getChannel(X, indX[i + r_start], best_feature)
				@logmsg DTDetail " Instance $(i)/$(n_instances)" channel Sf[i]
				(satisfied,S[indX[i + r_start]]) = ModalLogic.modalStep(Sf[i], best_relation, channel, best_test_operator, best_threshold)
				unsatisfied_flags[i] = !satisfied # I'm using unsatisfied because then sorting puts YES instances first but TODO use the inverse sorting and use satisfied flag instead
			end

			@logmsg DTOverview " Branch ($(sum(unsatisfied_flags))+$(n_instances-sum(unsatisfied_flags))=$(n_instances) samples) on condition: $(display_modal_test(best_relation, best_test_operator, featureSet[best_feature], best_threshold)), purity $(best_purity)"

			@logmsg DTDetail " unsatisfied_flags" unsatisfied_flags

			# TODO this is only a consistency check
			# TODO bring back if best_unsatisfied != unsatisfied_flags || best_nl != n_instances-sum(unsatisfied_flags) || length(unique(unsatisfied_flags)) == 1
			if best_nl != n_instances-sum(unsatisfied_flags) || length(unique(unsatisfied_flags)) == 1
				errStr = "Something's wrong with the optimization steps.\n"
				errStr *= "Branch ($(sum(unsatisfied_flags))+$(n_instances-sum(unsatisfied_flags))=$(n_instances) samples) on condition: $(display_modal_test(best_relation, best_test_operator, featureSet[best_feature], best_threshold)), purity $(best_purity)"
				if length(unique(unsatisfied_flags)) == 1
					errStr *= "Uninformative split.\n$(unsatisfied_flags)\n"
				end
				# TODO bring back if best_unsatisfied != unsatisfied_flags || best_nl != n_instances-sum(unsatisfied_flags)
				# if best_nl != n_instances-sum(unsatisfied_flags)
				if best_nl != n_instances-sum(unsatisfied_flags)
					# TODO bring back errStr *= "Different unsatisfied and best_unsatisfied:\ncomputed: $(best_unsatisfied)\n$(best_nl)\nactual: $(unsatisfied_flags)\n$(n_instances-sum(unsatisfied_flags))\n"
					# errStr *= "Different unsatisfied and best_unsatisfied:\ncomputed: $(best_unsatisfied)\n$(best_nl)\nactual: $(unsatisfied_flags)\n$(n_instances-sum(unsatisfied_flags))\n"
					errStr *= "Different unsatisfied:\ncomputed: $(best_nl)\nactual: $(unsatisfied_flags)\n$(n_instances-sum(unsatisfied_flags))\n"
				end
				for i in 1:n_instances
					errStr *= "$(ModalLogic.getChannel(X, indX[i + r_start], best_feature))\t$(Sf[i])\t$(!(unsatisfied_flags[i]==1))\t$(S[indX[i + r_start]])\n";
				end
				# throw(Base.ErrorException(errStr))
				println("ERROR! " * errStr)
                                # TODO bring this error back
			end

			@logmsg DTDetail "pre-partition" region indX[region] unsatisfied_flags
			node.split_at = util.partition!(indX, unsatisfied_flags, 0, region)
			@logmsg DTDetail "post-partition" indX[region] node.split_at

			# For debug:
			# indX = rand(1:10, 10)
			# unsatisfied_flags = rand([1,0], 10)
			# partition!(indX, unsatisfied_flags, 0, 1:10)
			
			# Sort [Xf, Yf, Wf, Sf and indX] by Xf
			# util.q_bi_sort!(unsatisfied_flags, indX, 1, n_instances, r_start)
			# node.split_at = searchsortedfirst(unsatisfied_flags, true)
		end
	end

	# Split node at a previously-set node.split_at value.
	# The children inherits some of the data
	@inline function fork!(node::NodeMeta{S,U}) where {S,U}
		ind = node.split_at
		region = node.region
		depth = node.depth+1
		mdepth = (node.modality == RelationId ? node.modal_depth : node.modal_depth+1)
		@logmsg DTDetail "fork!(...): " node ind region mdepth
		# no need to copy because we will copy at the end
		node.l = NodeMeta{S,U}(region[    1:ind], depth, mdepth)
		node.r = NodeMeta{S,U}(region[ind+1:end], depth, mdepth)
	end

	function check_input(
			X                   :: OntologicalDataset{T, N},
			Y                   :: AbstractVector{S},
			W                   :: AbstractVector{U},
			loss_function       :: Function,
			n_subfeatures       :: Int,
			max_depth           :: Int,
			min_samples_leaf    :: Int,
			min_loss_at_leaf    :: AbstractFloat,
			min_purity_increase :: AbstractFloat) where {T, S, U, N}
		n_instances, n_attrs = n_samples(X), n_attributes(X)

		if length(Y) != n_instances
			throw("dimension mismatch between X and Y ($(size(X)) vs $(size(Y))")
		elseif length(W) != n_instances
			throw("dimension mismatch between X and W ($(size(X)) vs $(size(W))")
		elseif max_depth < -1
			throw("unexpected value for max_depth: $(max_depth) (expected:"
				* " max_depth >= 0, or max_depth = -1 for infinite depth)")
		elseif n_attrs < n_subfeatures
			throw("total number of features $(n_attrs) is less than the number "
				* "of features required at each split $(n_subfeatures)")
		elseif n_subfeatures < 0
			throw("total number of features $(n_subfeatures) must be >= zero ")
		elseif min_samples_leaf < 1
			throw("min_samples_leaf must be a positive integer "
				* "(given $(min_samples_leaf))")
		elseif loss_function in [util.gini, util.zero_one] && (min_loss_at_leaf > 1.0 || min_loss_at_leaf <= 0.0)
			throw("min_loss_at_leaf for loss $(loss_function) must be in (0,1]"
				* "(given $(min_loss_at_leaf))")
		end

		# TODO make sure how missing, nothing, NaN & infinite can be handled
		# TODO make these checks part of the dataset interface!
		if nothing in X.domain
			throw("Warning! This algorithm doesn't allow nothing values in X.domain")
		elseif any(isnan.(X.domain)) # TODO make sure that this does its job.
			throw("Warning! This algorithm doesn't allow NaN values in X.domain")
		elseif nothing in Y
			throw("Warning! This algorithm doesn't allow nothing values in Y")
		# elseif any(isnan.(Y))
		# 	throw("Warning! This algorithm doesn't allow NaN values in Y")
		elseif nothing in W
			throw("Warning! This algorithm doesn't allow nothing values in W")
		elseif any(isnan.(W))
			throw("Warning! This algorithm doesn't allow NaN values in W")
		end

		# if loss_function in [util.entropy]
		# 	min_loss_at_leaf_thresh = 0.75 # min_purity_increase 0.01
		# 	min_purity_increase_thresh = 0.5
		# 	if (min_loss_at_leaf >= min_loss_at_leaf_thresh)
		# 		println("Warning! It is advised to use min_loss_at_leaf<$(min_loss_at_leaf_thresh) with loss $(loss_function)"
		# 			* "(given $(min_loss_at_leaf))")
		# 	elseif (min_purity_increase >= min_purity_increase_thresh)
		# 		println("Warning! It is advised to use min_loss_at_leaf<$(min_purity_increase_thresh) with loss $(loss_function)"
		# 			* "(given $(min_purity_increase))")
		# end
	end

	function optimize_tree_parameters!(
			X               :: OntologicalDataset{T, N},
			initCondition   :: DecisionTree._initCondition,
			useRelationAll  :: Bool,
			useRelationId	  :: Bool,
			test_operators  :: AbstractVector{<:TestOperator}
		) where {T, N}

		# Adimensional ontological datasets:
		#  flatten to adimensional case + strip of all relations from the ontology
		if prod(channel_size(X)) == 1
			if (length(X.ontology.relationSet) > 0)
				warn("The OntologicalDataset provided has degenerate channel_size $(channel_size(X)), and more than 0 relations: $(X.ontology.relationSet).")
			end
			# X = OntologicalDataset{T, 0}(ModalLogic.strip_ontology(X.ontology), @views ModalLogic.strip_domain(X.domain))
		end

		ontology_relations = deepcopy(X.ontology.relationSet)

		# Fix test_operators order
		test_operators = unique(test_operators)
		ModalLogic.sort_test_operators!(test_operators)
		
		# Adimensional operators:
		#  in the adimensional case, some pairs of operators (e.g. <= and >)
		#  are complementary, and thus it is redundant to check both at the same node.
		#  We avoid this by only keeping one of the two operators.
		if prod(channel_size(X)) == 1
			# No ontological relation
			ontology_relations = []
			if test_operators ⊆ ModalLogic.all_lowlevel_test_operators
				test_operators = [TestOpGeq]
				# test_operators = filter(e->e ≠ TestOpGeq,test_operators)
			else
				warn("Test operators set includes non-lowlevel test operators. Update this part of the code accordingly.")
			end
		end

		# Softened operators:
		#  when the biggest world only has a few values, softened operators fallback
		#  to being hard operators
		max_world_wratio = 1/prod(channel_size(X))
		if TestOpGeq in test_operators
			test_operators = filter((e)->(typeof(e) != _TestOpGeqSoft || e.alpha < 1-max_world_wratio), test_operators)
		end
		if TestOpLeq in test_operators
			test_operators = filter((e)->(typeof(e) != _TestOpLeqSoft || e.alpha < 1-max_world_wratio), test_operators)
		end


		# Binary relations (= unary modal operators)
		# Note: the identity relation is the first, and it is the one representing
		#  propositional splits.
		
		if RelationId in ontology_relations
			throw("Found RelationId in ontology provided. Use useRelationId = true instead.")
			# ontology_relations = filter(e->e ≠ RelationId, ontology_relations)
			# useRelationId = true
		end

		if RelationAll in ontology_relations
			throw("Found RelationAll in ontology provided. Use useRelationAll = true instead.")
			# ontology_relations = filter(e->e ≠ RelationAll, ontology_relations)
			# useRelationAll = true
		end

		relationSet = [RelationId, RelationAll, ontology_relations...]
		relationId_id = 1
		relationAll_id = 2
		ontology_relation_ids = map((x)->x+2, 1:length(ontology_relations))

		needToComputeRelationAll = (useRelationAll || (initCondition == startWithRelationAll))

		# Modal relations to compute gammas for
		inUseRelation_ids = if needToComputeRelationAll
			[relationAll_id, ontology_relation_ids...]
		else
			ontology_relation_ids
		end

		# Relations to use at each split
		availableRelation_ids = []

		if useRelationId
			push!(availableRelation_ids, relationId_id)
		end
		if useRelationAll
			push!(availableRelation_ids, relationAll_id)
		end

		availableRelation_ids = [availableRelation_ids..., ontology_relation_ids...]

		(
			test_operators, relationSet,
			relationId_id, relationAll_id,
			inUseRelation_ids, availableRelation_ids
		)
	end

	function _fit(
			X                       :: OntologicalDataset{T, N, WorldType},
			Y                       :: AbstractVector{Label},
			W                       :: AbstractVector{U},
			loss                    :: Function,
			n_classes               :: Int,
			n_subfeatures           :: Int,
			max_depth               :: Int,
			min_samples_leaf        :: Int, # TODO generalize to min_samples_leaf_relative and min_weight_leaf
			min_purity_increase     :: AbstractFloat,
			min_loss_at_leaf        :: AbstractFloat,
			n_subrelations           :: Function,
			initCondition           :: DecisionTree._initCondition,
			useRelationAll          :: Bool,
			useRelationId           :: Bool,
			test_operators          :: AbstractVector{<:TestOperator},
			rng = Random.GLOBAL_RNG :: Random.AbstractRNG;
			gammas                  :: Union{GammaType{NTO, Ta},Nothing} = nothing) where {T, U, N, NTO, Ta, WorldType<:AbstractWorld}

		if N != ModalLogic.worldTypeDimensionality(WorldType)
			error("ERROR! Dimensionality mismatch: can't interpret worldType $(WorldType) (dimensionality = $(ModalLogic.worldTypeDimensionality(WorldType)) on OntologicalDataset of dimensionality = $(N)")
		end
		
		# Dataset sizes
		n_instances = n_samples(X)

		# Initialize world sets
		w0params =
			if initCondition == startWithRelationAll
				[ModalLogic.emptyWorld]
			elseif initCondition == startAtCenter
				[ModalLogic.centeredWorld, channel_size(X)...]
			elseif typeof(initCondition) <: DecisionTree._startAtWorld
				[initCondition.w]
		end
		S = WorldSet{WorldType}[[WorldType(w0params...)] for i in 1:n_instances]

		# Array memory for class counts
		nc  = Vector{U}(undef, n_classes)
		ncl = Vector{U}(undef, n_classes)
		ncr = Vector{U}(undef, n_classes)

		# Array memory for dataset
		# Xf = Array{T, N+1}(undef, channel_size(X)..., n_instances)
		Yf = Vector{Label}(undef, n_instances)
		Wf = Vector{U}(undef, n_instances)
		Sf = Vector{WorldSet{WorldType}}(undef, n_instances)
		
		featureSet = 1:n_attributes(X)

		(
			# X,
			test_operators, relationSet,
			relationId_id, relationAll_id,
			inUseRelation_ids, availableRelation_ids
		) = optimize_tree_parameters!(X, initCondition, useRelationAll, useRelationId, test_operators)

		if (length(availableRelation_ids) == 0)
			throw("No available relation! Allow propositional splits with useRelationId=true")
		end

		if isnothing(gammas)
			# Calculate gammas
			#  A gamma, for a given feature f, world w, relation X and test_operator ⋈, is 
			#  the unique value γ for which w ⊨ <X> f ⋈ γ and:
			#  if polarity(⋈) == true:      ∀ a > γ:    w ⊭ <X> f ⋈ a
			#  if polarity(⋈) == false:     ∀ a < γ:    w ⊭ <X> f ⋈ a
			
			gammas = DecisionTree.computeGammas(X, test_operators, relationSet, relationId_id, inUseRelation_ids)
			# using BenchmarkTools; gammas = @btime DecisionTree.computeGammas($X, $$test_operators, $relationSet, $relationId_id, $inUseRelation_ids)
		else
			DecisionTree.checkGammasConsistency(gammas, X, test_operators, relationSet)
		end

		# Let the core algorithm begin!

		# Sample indices (array of indices that will be sorted and partitioned across the leaves)
		indX = collect(1:n_instances)
		# Create root node
		root = NodeMeta{T,Float64}(1:n_instances, 0, 0)
		# Stack of nodes to process
		stack = Tuple{NodeMeta{T,Float64},Bool}[(root,(initCondition == startWithRelationAll))]
		# The first iteration is treated sightly differently
		@inbounds while length(stack) > 0
			# Pop node and process it
			(node,onlyUseRelationAll) = pop!(stack)
			_split!(
				X, Y, W, S,
				loss, node,
				n_subfeatures,
				max_depth,
				min_samples_leaf,
				min_loss_at_leaf,
				min_purity_increase,
				n_subrelations,
				test_operators,
				indX,
				nc, ncl, ncr, 
				# Xf, 
				Yf, Wf, Sf, gammas,
				relationSet,
				(onlyUseRelationAll ? [relationAll_id] : availableRelation_ids),
				featureSet,
				rng,
				)
			# After processing, if needed, perform the split and push the two children for a later processing step
			if !node.is_leaf
				fork!(node)
				# Note: the left (positive) child is not limited to RelationAll, whereas the right child is only if the current node is as well.
				push!(stack, (node.l, false))
				push!(stack, (node.r, onlyUseRelationAll))
			end
		end

		return (root, indX)
	end

	function fit(;
			# In the modal case, dataset instances are Kripke models.
			# In this implementation, we don't accept a generic Kripke model in the explicit form of
			#  a graph; instead, an instance is a dimensional domain (e.g. a matrix or a 3D matrix) onto which
			#  worlds and relations are determined by a given Ontology.
			X                       :: OntologicalDataset{T, N},
			Y                       :: AbstractVector{S},
			W                       :: Union{Nothing, AbstractVector{U}},
			gammas                  :: Union{GammaType{NTO, Ta},Nothing} = nothing,
			loss = util.entropy     :: Function,
			n_subfeatures           :: Int,
			max_depth               :: Int,
			min_samples_leaf        :: Int,
			min_purity_increase     :: AbstractFloat,
			min_loss_at_leaf        :: AbstractFloat, # TODO add this to scikit's interface.
			n_subrelations           :: Function,
			initCondition           :: DecisionTree._initCondition,
			useRelationAll          :: Bool,
			useRelationId           :: Bool,
			test_operators          :: AbstractVector{<:TestOperator} = [TestOpGeq, TestOpLeq],
			rng = Random.GLOBAL_RNG :: Random.AbstractRNG) where {T, S, U, N, NTO, Ta}

		# Obtain the dataset's "outer size": number of samples and number of features
		n_instances = n_samples(X)

		# Use unary weights if no weight is supplied
		if isnothing(W)
			# TODO optimize w in the case of all-ones: write a subtype of AbstractVector:
			#  AllOnesVector, so that getindex(W, i) = 1 and sum(W) = size(W).
			#  This allows the compiler to optimize constants at compile-time
			W = fill(1, n_instances)
		end

		# Check validity of the input
		check_input(
			X, Y, W,
			loss,
			n_subfeatures,
			max_depth,
			min_samples_leaf,
			min_loss_at_leaf,
			min_purity_increase,
			)

		# Translate labels to categorical form
		labels, Y_ = util.assign(Y)
		# print(labels, Y_)

		# Call core learning function
		root, indX = _fit(
			X, Y_, W,
			loss,
			length(labels),
			n_subfeatures,
			max_depth,
			min_samples_leaf,
			min_purity_increase,
			min_loss_at_leaf,
			n_subrelations,
			initCondition,
			useRelationAll,
			useRelationId,
			test_operators,
			rng;
			gammas = gammas)

		return Tree{T, S}(root, labels, indX, initCondition)
	end
end
