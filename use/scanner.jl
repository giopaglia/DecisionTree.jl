using Pkg
Pkg.activate("..")
using Revise

using DecisionTree
using DecisionTree.ModalLogic

import Random
my_rng() = Random.MersenneTwister(1) # Random.GLOBAL_RNG

using Logging
using ResumableFunctions
using IterTools

using BenchmarkTools
# using ScikitLearnBase
using Statistics
using Test
# using Profile
# using PProf


using DataStructures


using SHA
using Serialization
import JLD2
import Dates

function get_hash_sha256(var)::String
	io = IOBuffer();
	serialize(io, var)
	result = bytes2hex(sha256(take!(io)))
	close(io)

	result
end

abstract type Support end

mutable struct ForestEvaluationSupport <: Support
	f::Union{Nothing,Support,AbstractVector{Forest{S}}} where {S}
	f_args::NamedTuple{T, N} where {T, N}
	cm::Union{Nothing,AbstractVector{<:ConfusionMatrix}}
	time::Dates.Millisecond
	enqueued::Bool
	ForestEvaluationSupport(f_args) = new(nothing, f_args, nothing, Dates.Millisecond(0), false)
end

function will_produce_same_forest_with_different_number_of_trees(f1::ForestEvaluationSupport, f2::ForestEvaluationSupport)
	# TODO: find a smart way to handle this (just not needed for now)
	@assert length(f1.f_args) == length(f2.f_args) "Can't compare two forests with different number of arguments."
	for (k, v1) in zip(keys(f1.f_args), values(f1.f_args))
		# do not compare n_trees
		if k == :n_trees
			continue
		end
		if v1 != f2.f_args[k]
			return false
		end
	end
	true
end

function human_readable_time(ms::Dates.Millisecond)::String
	result = ms.value / 1000
	seconds = round(Int64, result % 60)
	result /= 60
	minutes = round(Int64, result % 60)
	result /= 60
	hours = round(Int64, result % 24)
	return string(string(hours; pad=2), ":", string(minutes; pad=2), ":", string(seconds; pad=2))
end

function checkpoint_stdout(string::String)
	println("● ", Dates.format(Dates.now(), "[ dd/mm/yyyy HH:MM:SS ] "), string)
	flush(stdout)
end

function display_cm_as_row(cm::ConfusionMatrix)
	"$(round(cm.overall_accuracy*100, digits=2))%\t" *
	"$(join(round.(cm.sensitivities.*100, digits=2), "%\t"))%\t" *
	"$(join(round.(cm.PPVs.*100, digits=2), "%\t"))%\t" *
	"||\t" *
	# "$(round(cm.mean_accuracy*100, digits=2))%\t" *
	"$(round(cm.kappa*100, digits=2))%\t" *
	# "$(round(DecisionTree.macro_F1(cm)*100, digits=2))%\t" *
	# "$(round.(cm.accuracies.*100, digits=2))%\t" *
	"$(round.(cm.F1s.*100, digits=2))%\t" *
	# "$(round.(cm.sensitivities.*100, digits=2))%\t" *
	# "$(round.(cm.specificities.*100, digits=2))%\t" *
	# "$(round.(cm.PPVs.*100, digits=2))%\t" *
	# "$(round.(cm.NPVs.*100, digits=2))%\t" *
	# "|||\t" *
	# "$(round(DecisionTree.macro_weighted_F1(cm)*100, digits=2))%\t" *
	# # "$(round(DecisionTree.macro_sensitivity(cm)*100, digits=2))%\t" *
	# "$(round(DecisionTree.macro_weighted_sensitivity(cm)*100, digits=2))%\t" *
	# # "$(round(DecisionTree.macro_specificity(cm)*100, digits=2))%\t" *
	# "$(round(DecisionTree.macro_weighted_specificity(cm)*100, digits=2))%\t" *
	# # "$(round(DecisionTree.mean_PPV(cm)*100, digits=2))%\t" *
	# "$(round(DecisionTree.macro_weighted_PPV(cm)*100, digits=2))%\t" *
	# # "$(round(DecisionTree.mean_NPV(cm)*100, digits=2))%\t" *
	# "$(round(DecisionTree.macro_weighted_NPV(cm)*100, digits=2))%\t" *
	""
end


include("caching.jl")
include("table-printer.jl")
include("progressive-iterator-manager.jl")
include("datasets.jl")
include("dataset-utils.jl")


# Slice & split the dataset according to dataset_slices & split_threshold
# The instances for which the full StumpFeatModalDataset is computed are either all, or the ones specified for training;
# This depends on whether the dataset is already splitted or not.
@resumable function generate_splits(dataset, split_threshold, round_dataset_to_datatype, save_datasets, run_name, dataset_slices, data_savedir, buildModalDatasets_fun)
	if split_threshold != false # Dataset is to be splitted
		
		# Unpack dataset
		X, Y = dataset

		# Apply scaling
		if round_dataset_to_datatype != false
			X, Y = round_dataset((X, Y), round_dataset_to_datatype)
		end
		
		# Compute mffmd for the full set of instances
		X_to_train, X_to_test = buildModalDatasets_fun(X, X)
		
		if save_datasets
			train = (X_to_train, Y)
			JLD2.@save (data_savedir * "/datasets/$(run_name)-train.jld") train
			test = (X_to_test, Y)
			JLD2.@save (data_savedir * "/datasets/$(run_name)-test.jld") test
		end

		for (slice_id,dataset_slice) in dataset_slices

			println("Dataset_slice = (" * (!isnothing(dataset_slice) ? "$(length(dataset_slice))) -> $(dataset_slice)" : "nothing"))

			# Slice instances (for balancing, for example)
			X_to_train_slice, X_to_test_slice, Y_slice =
				if isnothing(dataset_slice)
					(X_to_train, X_to_test, Y,)
				else
					(
						ModalLogic.slice_dataset(X_to_train, dataset_slice),
						ModalLogic.slice_dataset(X_to_test,  dataset_slice),
						Y[dataset_slice],
					)
			end
			
			# println(" train dataset:")
			# println(display_structure(X_train_slice))
			# println(" test  dataset:")
			# println(display_structure(X_test_slice))

			# Split in train/test
			(X_train_slice, Y_train_slice), _ = traintestsplit((X_to_train_slice, Y_slice), split_threshold)
			_, (X_test_slice, Y_test_slice)   = traintestsplit((X_to_test_slice,  Y_slice), split_threshold)
			
			if save_datasets
				JLD2.@save (data_savedir * "/datasets/$(run_name)-$(slice_id)-dataset_slice.jld") dataset_slice
				sliced = (X_to_train_slice, Y_slice)
				JLD2.@save (data_savedir * "/datasets/$(run_name)-$(slice_id)-sliced.jld") sliced
				sliced_train = (X_train_slice, Y_train_slice)
				JLD2.@save (data_savedir * "/datasets/$(run_name)-$(slice_id)-sliced_train.jld") sliced_train
				sliced_test = (X_test_slice, Y_test_slice)
				JLD2.@save (data_savedir * "/datasets/$(run_name)-$(slice_id)-sliced_test.jld")  sliced_test
			end

			@yield slice_id, ((X_train_slice, Y_train_slice), (X_test_slice, Y_test_slice))
		end

	else # Dataset is already splitted

		# Unpack dataset
		(X_train, Y_train), (X_test, Y_test) = dataset

		# Apply scaling
		if round_dataset_to_datatype != false
			(X_train, Y_train), (X_test,  Y_test) = round_dataset(((X_train, Y_train), (X_test,  Y_test)), round_dataset_to_datatype)
		end
		
		# Compute mffmd for the training instances
		X_train, X_test = buildModalDatasets_fun(X_train, X_test)

		if save_datasets
			train = (X_train, Y_train)
			JLD2.@save (data_savedir * "/datasets/$(run_name)-train.jld") train
			test = (X_test, Y_test)
			JLD2.@save (data_savedir * "/datasets/$(run_name)-test.jld") test
		end

		# Slice *training* instances (for balancing, for example)
		for (slice_id,dataset_slice) in dataset_slices

			println("Dataset_slice = (" * (!isnothing(dataset_slice) ? "$(length(dataset_slice))) -> $(dataset_slice)" : "nothing"))

			X_train_slice, Y_train_slice =
				if isnothing(dataset_slice)
					(X_train, Y_train,)
				else
					(
					ModalLogic.slice_dataset(X_train, dataset_slice),
					Y_train[dataset_slice],
					)
				end

			if save_datasets
				JLD2.@save (data_savedir * "/datasets/$(run_name)-$(slice_id)-dataset_slice.jld") dataset_slice
				sliced_train = (X_train_slice, Y_train_slice)
				JLD2.@save (data_savedir * "/datasets/$(run_name)-$(slice_id)-sliced_train.jld") sliced_train
			end
			
			@yield slice_id, ((X_train_slice, Y_train_slice), (X_test, Y_test))
		end
	end
end

# This function transforms bare MatricialDatasets into modal datasets in the form of ontological or featmodal dataset
#  The train dataset, unless use_ontological_form, is transformed in featmodal form, which is optimized for training.
#  The test dataset is kept in ontological form
# function buildModalDatasets(Xs_train_all::Union{MatricialDataset,Vector{<:MatricialDataset}}, X_test::Union{MatricialDataset,Vector{<:MatricialDataset}})	
function buildModalDatasets(Xs_train_all, X_test, data_modal_args, modal_args, use_ontological_form, data_savedir, legacy_gammas_check, timing_mode, save_datasets)

	if Xs_train_all isa MatricialDataset
		Xs_train_all = [Xs_train_all]
	end
	if X_test isa MatricialDataset
		X_test = [X_test]
	end
	
	# The test dataset is kept in its ontological form
	X_test = MultiFrameModalDataset([OntologicalDataset(data_modal_args.ontology, X) for X in X_test])

	# The train dataset is either kept in ontological form, or processed into stump form (which allows for optimized learning)
	Xs_train_all = 
		if use_ontological_form
			MultiFrameModalDataset([OntologicalDataset(data_modal_args.ontology, X) for X in Xs_train_all])
		else
			WorldType = world_type(data_modal_args.ontology)

			Xs_train_all_multiframe_stump_fmd = StumpFeatModalDataset{<:Real,<:AbstractWorld}[]

			# Compute stump for each frame
			for (i_frame, X_train_all) in enumerate(Xs_train_all)
				println("Frame $(i_frame)/$(length(Xs_train_all))")

				# X_train_all = OntologicalDataset{eltype(X_train_all)}(data_modal_args.ontology,X_train_all)
				X_train_all = OntologicalDataset(data_modal_args.ontology, X_train_all)
				
				needToComputeRelationGlob =
					WorldType != OneWorld && (
						(modal_args.useRelationGlob || (modal_args.initConditions == DecisionTree.startWithRelationGlob))
							|| ((modal_args.initConditions isa AbstractVector) && modal_args.initConditions[i_frame] == DecisionTree.startWithRelationGlob)
					)
				########################################################################
				########################################################################
				########################################################################
				
				# Prepare features
				# TODO generalize
				
				features = FeatureTypeFun[]

				for i_attr in 1:n_attributes(X_train_all)
					for test_operator in data_modal_args.test_operators
						if test_operator == TestOpGeq
							push!(features, ModalLogic.AttributeMinimumFeatureType(i_attr))
						elseif test_operator == TestOpLeq
							push!(features, ModalLogic.AttributeMaximumFeatureType(i_attr))
						elseif test_operator isa _TestOpGeqSoft
							push!(features, ModalLogic.AttributeSoftMinimumFeatureType(i_attr, test_operator.alpha))
						elseif test_operator isa _TestOpLeqSoft
							push!(features, ModalLogic.AttributeSoftMaximumFeatureType(i_attr, test_operator.alpha))
						else
							error("Unknown test_operator type: $(test_operator), $(typeof(test_operator))")
						end
					end
				end

				featsnops = Vector{<:TestOperatorFun}[
					if any(map(t->isa(feature,t), [AttributeMinimumFeatureType, AttributeSoftMinimumFeatureType]))
						[≥]
					elseif any(map(t->isa(feature,t), [AttributeMaximumFeatureType, AttributeSoftMaximumFeatureType]))
						[≤]
					else
						error("Unknown feature type: $(feature), $(typeof(feature))")
						[≥, ≤]
					end for feature in features
				]

				########################################################################
				########################################################################
				########################################################################

				sfmd_c(X_train_all, features, featsnops, needToComputeRelationGlob) = begin
					if timing_mode == :none
						StumpFeatModalDataset(X_train_all, features, featsnops, computeRelationGlob = needToComputeRelationGlob);
					elseif timing_mode == :time
						@time StumpFeatModalDataset(X_train_all, features, featsnops, computeRelationGlob = needToComputeRelationGlob);
					elseif timing_mode == :btime
						@btime StumpFeatModalDataset($X_train_all, $features, $featsnops, computeRelationGlob = $needToComputeRelationGlob);
					end
				end

				stump_fmd = 
					if save_datasets
						@cache "stump_fmd" data_savedir (X_train_all, features, featsnops, needToComputeRelationGlob) sfmd_c
					else
						sfmd_c(X_train_all, features, featsnops, needToComputeRelationGlob)
					end
				
				# println("Ontological form" * display_structure(X_train_all))
				# println("Stump form" * display_structure(stump_fmd))

				########################################################################
				########################################################################
				######################## LEGACY CHECK WITH GAMMAS ######################
				########################################################################
				########################################################################

				if legacy_gammas_check != false && WorldType != OneWorld # TODO gammas are faulty in the propositional case (= with OneWorld)
					relationSet = [RelationId, RelationGlob, data_modal_args.ontology.relationSet...]
					relationId_id = 1
					relationGlob_id = 2
					ontology_relation_ids = map((x)->x+2, 1:length(data_modal_args.ontology.relationSet))

					# Modal relations to compute gammas for
					inUseRelation_ids = if needToComputeRelationGlob
						[relationGlob_id, ontology_relation_ids...]
					else
						ontology_relation_ids
					end

					# Generate path to gammas jld file
					gammas_c(X_train_all,test_operators,relationSet,relationId_id,inUseRelation_ids) = begin
						if timing_mode == :none
							DecisionTree.computeGammas(X_train_all,test_operators,relationSet,relationId_id,inUseRelation_ids);
						elseif timing_mode == :time
							@time DecisionTree.computeGammas(X_train_all,test_operators,relationSet,relationId_id,inUseRelation_ids);
						elseif timing_mode == :btime
							@btime DecisionTree.computeGammas($X_train_all,$test_operators,$relationSet,$relationId_id,$inUseRelation_ids);
						end
					end

					gammas = 
					if save_datasets
						@cache "gammas" data_savedir (X_train_all,data_modal_args.test_operators,relationSet,relationId_id,inUseRelation_ids) gammas_c
					else
						gammas_c(X_train_all,test_operators,relationSet,relationId_id,inUseRelation_ids)
					end

					
					println("Gammas form\t\t$(sizeof(gammas)/1024/1024 |> x->round(x, digits=2)) MBs\t(shape $(size(gammas)), type $(typeof(gammas)))")
					
					# Check consistency between FeaturedWorldDataset and modalDataset

					if legacy_gammas_check == true
						checkpoint_stdout("Start checking propositional consistency...")

						# propositional decisions
						n_checks = 0
						for i_instance in 1:n_samples(X_train_all)
							instance = ModalLogic.getInstance(X_train_all, i_instance)
							i_feature = 1
							for i_attribute in 1:n_attributes(X_train_all)
								for (i_test_operator,test_operator) in enumerate(data_modal_args.test_operators)
									for w in ModalLogic.enumAll(WorldType, ModalLogic.inst_channel_size(instance)...)
										
										g = DecisionTree.readGamma(gammas,i_test_operator,w,i_instance,1,i_attribute)
										m = get_gamma(stump_fmd, i_instance, w, features[i_feature])
										n_checks += 1

										if g != m
											println("FeaturedWorldDataset check: g != m\n$(g)\n$(m)")
											println("i_test_operator=$(i_test_operator)")
											println("w=$(w)")
											println("i_instance=$(i_instance)")
											println("i_attribute=$(i_attribute)")
											print("instance: ")
											println(ModalLogic.getInstanceAttribute(instance, i_attribute))
											error("aoe")
										end
									end
									i_feature += 1
								end
							end
						end
						
						# global decisions
						if !isnothing(stump_fmd.fmd_g)
							checkpoint_stdout("Start checking global consistency ($n_checks checks so far)...")
							firstWorld = WorldType(ModalLogic.firstWorld)
							for i_instance in 1:n_samples(X_train_all)
								instance = ModalLogic.getInstance(X_train_all, i_instance)
								i_feature = 1
								for i_attribute in 1:n_attributes(X_train_all)
									for (i_test_operator,test_operator) in enumerate(data_modal_args.test_operators)
										
										g = DecisionTree.readGamma(gammas,i_test_operator,firstWorld,i_instance,2,i_attribute)
										m = ModalLogic.get_global_gamma(stump_fmd, i_instance, features[i_feature], featsnops[i_feature][1])
										n_checks += 1
										
										# println(g,m)

										if g != m
											println("fmd_g check: g != m")
											println("$(g)")
											println("$(m)")
											println("i_test_operator=$(i_test_operator)")
											println("test_operator=$(data_modal_args.test_operators[i_test_operator])")
											println("i_instance=$(i_instance)")
											println("i_attribute=$(i_attribute)")
											print("instance: ")
											println(ModalLogic.getInstanceAttribute(instance, i_attribute))
											print(instance)
											# error("aoe")
											readline()
										
										end
										i_feature += 1
									end
								end
							end
						end

						# modal decisions
						checkpoint_stdout("Start checking modal consistency ($n_checks checks so far)...")
						relations = X_train_all.ontology.relationSet
						for i_instance in 1:n_samples(X_train_all)
							instance = ModalLogic.getInstance(X_train_all, i_instance)
							i_feature = 1
							for i_attribute in 1:n_attributes(X_train_all)
								i_feature2 = nothing
								for (i_relation,relation) in enumerate(relations)
									i_feature2 = i_feature
									for (i_test_operator,test_operator) in enumerate(data_modal_args.test_operators)
										test_operator = featsnops[i_feature2][1]
										for w in ModalLogic.enumAll(WorldType, ModalLogic.inst_channel_size(instance)...)
											

											g = DecisionTree.readGamma(gammas,i_test_operator,w,i_instance,2+i_relation,i_attribute)
											m = ModalLogic.get_modal_gamma(stump_fmd, i_instance, w, relation, features[i_feature2], test_operator)
											n_checks += 1
											
											if g != m
												println("fmd_m check: g != m")
												
												println("$(g)")
												println("$(m)")

												println("i_relation=$(i_relation), relation=$(relation)")
												println("w=$(w)")
												println("i_instance=$(i_instance)")
												println("i_attribute=$(i_attribute)")

												println("i_test_operator=$(i_test_operator)")
												println("test_operator=$(test_operator)")
												println("test_operator=$(data_modal_args.test_operators[i_test_operator])")
												println("i_feature2=$(i_feature2) (i_feature=$(i_feature))")

												print("channel: ")
												println(ModalLogic.getInstanceAttribute(instance, i_attribute))
												# error("aoe")
												readline()
											end
										end
										i_feature2 += 1
									end
								end
								i_feature = i_feature2
							end
						end
						println("Checked consistency for $(n_checks) gammas. All clear!")
					end
				end

				########################################################################
				########################################################################
				########################################################################
				########################################################################
				########################################################################
				
				push!(Xs_train_all_multiframe_stump_fmd, stump_fmd)
			end
			
			MultiFrameModalDataset(Xs_train_all_multiframe_stump_fmd)
		end
		
		# println("Xs_train_all:")
		# println("  " * display_structure(Xs_train_all; indent = 2))

	Xs_train_all, X_test
end


function exec_scan(
		run_name                        ::String,
		dataset                         ::Tuple;
		### Training params
		train_seed                      = 1,
		modal_args                      = (),
		tree_args                       = [],
		tree_post_pruning_purity_thresh = [],
		forest_args                     = [],
		forest_runs                     = 1,
		optimize_forest_computation     = false,
		test_flattened                  = false,
		test_averaged                   = false,
		### Dataset params
		split_threshold                 ::Union{Bool,AbstractFloat} = 1.0,
		data_modal_args                 = (),
		dataset_slices                  ::Union{AbstractVector{<:Tuple{<:Any,<:AbstractVector{<:Integer}}},AbstractVector{<:AbstractVector{<:Integer}},Nothing} = nothing,
		round_dataset_to_datatype       ::Union{Bool,Type} = false,
		use_ontological_form            = false,
		### Run params
		results_dir                     ::String,
		data_savedir                    ::Union{String,Nothing} = nothing,
		tree_savedir                    ::Union{String,Nothing} = nothing,
		legacy_gammas_check             = false,
		log_level                       = DecisionTree.DTOverview,
		timing_mode                     ::Symbol = :time,
		### Misc
		save_datasets                   :: Bool = false,
		skip_training                   :: Bool = false,
		callback                        :: Function = identity,
	)

	go_tree(dataset, tree_args, rng) = begin
		(X_train,Y_train), (X_test,Y_test) = dataset
		started = Dates.now()
		T =
			if timing_mode == :none
				build_tree(X_train, Y_train; tree_args..., modal_args..., rng = rng)
			elseif timing_mode == :time
				@time build_tree(X_train, Y_train; tree_args..., modal_args..., rng = rng)
			elseif timing_mode == :btime
				@btime build_tree($X_train, $Y_train; $tree_args..., $modal_args..., rng = $rng)
			end
		Tt = Dates.now() - started
		println("Train tree:")
		print(T)

		if !isnothing(tree_savedir)
			tree_hash = get_hash_sha256(T)
			total_save_path = tree_savedir * "/tree_" * tree_hash * ".jld"
			mkpath(dirname(total_save_path))

			checkpoint_stdout("Saving tree to file $(total_save_path)...")
			JLD2.@save total_save_path T
		end

		# If not fulltraining
		if split_threshold != 1.0
			println("Test tree:")
			print_apply_tree(T, X_test, Y_test)
		end

		println(" test size = $(size(X_test))")
		cm = nothing
		for pruning_purity_threshold in sort(unique([(Float64.(tree_post_pruning_purity_thresh))...,1.0]))
			println(" Purity threshold $pruning_purity_threshold")
			
			T_pruned = prune_tree(T, pruning_purity_threshold)
			preds = apply_tree(T_pruned, X_test);
			cm = confusion_matrix(Y_test, preds)
			# @test cm.overall_accuracy > 0.99

			println("RESULT:\t$(run_name)\t$(tree_args)\t$(modal_args)\t$(pruning_purity_threshold)\t|\t$(display_cm_as_row(cm))")
			
			println(cm)
			# @show cm

			# println("nodes: ($(num_nodes(T_pruned)), height: $(height(T_pruned)))")
		end
		return (T, cm, Tt);
	end

	go_forest(dataset, f_args, rng; prebuilt_model::Union{Nothing,AbstractVector{Forest{S}}} = nothing) where {S} = begin
		(X_train,Y_train), (X_test,Y_test) = dataset
		Fs, Ft = 
			if isnothing(prebuilt_model)
				started = Dates.now()
				[
					if timing_mode == :none
						build_forest(X_train, Y_train; f_args..., modal_args..., rng = rng);
					elseif timing_mode == :time
						@time build_forest(X_train, Y_train; f_args..., modal_args..., rng = rng);
					elseif timing_mode == :btime
						@btime build_forest($X_train, $Y_train; $f_args..., $modal_args..., rng = $rng);
					end
					for i in 1:forest_runs
				], (Dates.now() - started)
			else
				println("Using slice of a prebuilt forest.")
				# !!! HUGE PROBLEM HERE !!! #
				# BUG: can't compute oob_error of a forest built slicing another forest!!!
				forests::Vector{Forest{S}} = []
				for f in prebuilt_model
					v_forest = @views f.trees[Random.randperm(rng, length(f.trees))[1:f_args.n_trees]]
					v_cms = @views f.cm[Random.randperm(rng, length(f.cm))[1:f_args.n_trees]]
					push!(forests, Forest{S}(v_forest, v_cms, 0.0))
				end
				forests, Dates.Millisecond(0)
			end

		for F in Fs
			print(F)
		end
		
		cms = ConfusionMatrix[]
		for F in Fs
			println(" test size = $(size(X_test))")
			
			preds = apply_forest(F, X_test);
			cm = confusion_matrix(Y_test, preds)
			# @test cm.overall_accuracy > 0.99

			println("RESULT:\t$(run_name)\t$(f_args)\t$(modal_args)\t$(display_cm_as_row(cm))")

			# println("  accuracy: ", round(cm.overall_accuracy*100, digits=2), "% kappa: ", round(cm.kappa*100, digits=2), "% ")
			for (i,row) in enumerate(eachrow(cm.matrix))
				for val in row
					print(lpad(val,3," "))
				end
				println("  " * "$(round(100*row[i]/sum(row), digits=2))%\t\t" * cm.classes[i])
			end

			println("Forest OOB Error: $(round.(F.oob_error.*100, digits=2))%")

			push!(cms, cm)
		end

		return (Fs, cms, Ft);
	end

	go(slice_id, dataset) = begin
		Ts = []
		Fs = []
		Tcms = []
		Fcms = []
		Tts = []
		Fts = []

		for (i_model, this_args) in enumerate(tree_args)
			checkpoint_stdout("Computing tree $(i_model) / $(length(tree_args))...")
			this_T, this_Tcm, this_Tt = go_tree(dataset, this_args, Random.MersenneTwister(train_seed))
			push!(Ts, this_T)
			push!(Tcms, this_Tcm)
			push!(Tts, this_Tt)
		end

		if optimize_forest_computation
			# initialize support structures
			forest_supports_user_order = Vector{ForestEvaluationSupport}(undef, length(forest_args)) # ordered as user gave them
			for (i_forest, f_args) in enumerate(forest_args)
				forest_supports_user_order[i_forest] = ForestEvaluationSupport(f_args)
			end

			# biggest forest first
			forest_supports_build_order = Vector{ForestEvaluationSupport}() # ordered with biggest forest first
			append!(forest_supports_build_order, forest_supports_user_order)
			sort!(forest_supports_build_order, by = f -> f.f_args.n_trees, rev = true)

			for (i, f) in enumerate(forest_supports_build_order)
				if f.enqueued
					continue
				end

				f.enqueued = true

				for j in i:length(forest_supports_build_order)
					if forest_supports_build_order[j].enqueued
						continue
					end

					if will_produce_same_forest_with_different_number_of_trees(f, forest_supports_build_order[j])
						# reference the forest of the "equivalent" Support structor
						# equivalent means has the same parameters except for the n_trees
						forest_supports_build_order[j].f = forest_supports_build_order[i]
						forest_supports_build_order[j].enqueued = true
					end
				end
			end

			for (i, f) in enumerate(forest_supports_build_order)
				checkpoint_stdout("Computing Random Forest $(i) / $(length(forest_supports_build_order))...")
				model = f

				while isa(model, ForestEvaluationSupport)
					model = model.f
				end

				forest_supports_build_order[i].f, forest_supports_build_order[i].cm, forest_supports_build_order[i].time = go_forest(dataset, f.f_args, Random.MersenneTwister(train_seed), prebuilt_model = model)
			end

			# put resulting forests in vector in the order the user gave them
			for (i, f) in enumerate(forest_supports_user_order)
				@assert f.f isa AbstractVector{Forest{S}} where {S} "This is not a Vector of Forests! eltype = $(eltype(f.f))"
				@assert f.cm isa AbstractVector{ConfusionMatrix} "This is not a Vector of ConfusionMatrix!"
				@assert length(f.f) == forest_runs "There is a support struct with less than $(forest_runs) forests: $(length(f.f))"
				@assert length(f.cm) == forest_runs "There is a support struct with less than $(forest_runs) confusion matrices: $(length(f.cm))"
				@assert f.f_args == forest_args[i] "f_args mismatch! $(f.f_args) == $(f_args[i])"

				push!(Fs, f.f)
				push!(Fcms, f.cm)
				push!(Fts, f.time)
			end
		else
			for (i_forest, f_args) in enumerate(forest_args)
				checkpoint_stdout("Computing Random Forest $(i_forest) / $(length(forest_args))...")
				this_F, this_Fcm, this_Ft = go_forest(dataset, f_args, Random.MersenneTwister(train_seed))
				push!(Fs, this_F)
				push!(Fcms, this_Fcm)
				push!(Fts, this_Ft)
			end
		end

		##############################################################################
		##############################################################################
		# PRINT RESULT IN FILES 
		##############################################################################
		##############################################################################

		# PRINT CONCISE
		concise_output_string = string(slice_id, results_col_sep, run_name, results_col_sep)
		for j in 1:length(tree_args)
			concise_output_string *= string(data_to_string(Ts[j], Tcms[j], Tts[j]; alt_separator=", ", separator = results_col_sep))
			concise_output_string *= string(results_col_sep)
		end
		for j in 1:length(forest_args)
			concise_output_string *= string(data_to_string(Fs[j], Fcms[j], Fts[j]; alt_separator=", ", separator = results_col_sep))
			concise_output_string *= string(results_col_sep)
		end
		concise_output_string *= string("\n")
		append_in_file(concise_output_file_path, concise_output_string)

		# PRINT FULL
		full_output_string = string(slice_id, results_col_sep, run_name, results_col_sep)
		for j in 1:length(tree_args)
			full_output_string *= string(data_to_string(Ts[j], Tcms[j], Tts[j]; start_s = "", end_s = "", alt_separator = results_col_sep))
			full_output_string *= string(results_col_sep)
		end
		for j in 1:length(forest_args)
			full_output_string *= string(data_to_string(Fs[j], Fcms[j], Fts[j]; start_s = "", end_s = "", alt_separator = results_col_sep))
			full_output_string *= string(results_col_sep)
		end
		full_output_string *= string("\n")
		append_in_file(full_output_file_path, full_output_string)

		callback(slice_id)

		Ts, Fs, Tcms, Fcms, Tts, Fts
	end
	

	##############################################################################
	##############################################################################
	# Output files
	##############################################################################
	##############################################################################

	concise_output_file_path = results_dir * "/grouped_in_models.csv"
	full_output_file_path = results_dir * "/full_columns.csv"

	results_col_sep = ";"

	# If the output files do not exists initilize them
	print_head(concise_output_file_path, tree_args, forest_args, separator = results_col_sep, tree_columns = [""], forest_columns = ["", "σ²", "t"], empty_columns_before = 2)
	print_head(full_output_file_path, tree_args, forest_args, separator = results_col_sep,
		forest_columns = [
			"K",    "sensitivity",    "specificity",    "precision",    "accuracy",    "oob_error",
			"σ² K", "σ² sensitivity", "σ² specificity", "σ² precision", "σ² accuracy", "σ² oob_error",
			"t"],
		empty_columns_before = 2
	)

	##############################################################################
	##############################################################################
	##############################################################################

	if isa(dataset_slices,AbstractVector{<:AbstractVector{<:Integer}})
		dataset_slices = enumerate(dataset_slices)
	elseif isnothing(dataset_slices)
		dataset_slices = [(0,nothing)]
	end

	##############################################################################
	##############################################################################
	##############################################################################

	println()
	println("executing run '$run_name'...")
	println("dataset type = ", typeof(dataset))
	println()
	println("train_seed   = ", train_seed)
	println("modal_args   = ", modal_args)
	println("tree_args    = ", tree_args)
	# println("tree_post_pruning_purity_thresh    = ", tree_post_pruning_purity_thresh)
	println("forest_args  = ", forest_args)
	println("forest_runs  = ", forest_runs)
	# println("forest_args  = ", length(forest_args), " × some forest_args structure")
	println()
	println("split_threshold   = ", split_threshold)
	println("data_modal_args   = ", data_modal_args)
	println("dataset_slices    = ($(length(dataset_slices)) dataset_slices)")

	# println("round_dataset_to_datatype   = ", round_dataset_to_datatype)
	# println("use_ontological_form   = ", use_ontological_form)
	# println("data_savedir   = ", data_savedir)
	# println("tree_savedir   = ", tree_savedir)
	# println("legacy_gammas_check   = ", legacy_gammas_check)
	# println("log_level   = ", log_level)
	# println("timing_mode   = ", timing_mode)
	println()

	old_logger = global_logger(ConsoleLogger(stderr, log_level))
	# global_logger(ConsoleLogger(stderr, Logging.Warn));
	# global_logger(ConsoleLogger(stderr, Logging.Info))
	# global_logger(ConsoleLogger(stderr, log_level))
	# global_logger(ConsoleLogger(stderr, DecisionTree.DTDebug))

	rets = []
	
	buildModalDatasets_fun = (X_train,X_test)->buildModalDatasets(X_train, X_test, data_modal_args, modal_args, use_ontological_form, data_savedir, legacy_gammas_check, timing_mode, save_datasets)

	for (slice_id,dataset) in generate_splits(dataset, split_threshold, round_dataset_to_datatype, save_datasets, run_name, dataset_slices, data_savedir, buildModalDatasets_fun)

		(X_train,Y_train), (X_test,Y_test) = dataset

		@assert n_samples(X_train) == length(Y_train)
		@assert n_samples(X_test) == length(Y_test)
		

		println("train dataset:")
		println("  " * display_structure(X_train; indent = 2))

		println("test  dataset:")
		println("  " * display_structure(X_test; indent = 2))

		if !skip_training
			# readline()

			# TODO
			# if test_flattened == true
			# 	# Flatten 
			# 	(X_train,Y_train), (X_test,Y_test) = dataset
			# 	X_train = ...
			# 	X_test = ...
			# 	flat_dataset = (X_train,Y_train), (X_test,Y_test)
			# 	push!(rets, go(flat_dataset))
			# end
			# test_averaged ...

			push!(rets, go(slice_id, dataset))
			
			# try
			# go(slice_id, dataset)
			# catch e
			# 	println("exec_run: An error occurred!")
			# 	println(e)
			# 	return;
			# end
			
		end
	end

	global_logger(old_logger);
	
	rets = zip(rets...)
	rets = map((r)->Iterators.flatten(r) |> collect, rets)
	
	rets
end