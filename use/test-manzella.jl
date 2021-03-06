# julia -i -t4 test-manzella.jl
# julia -i test-manzella.jl

include("scanner.jl")

rng = my_rng()

forest_args = [(
	n_subfeatures = x -> ceil(Int, sqrt(x)),
	n_trees = 100,
	partial_sampling = 1.0,
),(
	n_subfeatures = x -> ceil(Int, x / 2),
	n_trees = 100,
	partial_sampling = 1.0,
)]

tree_args = [
	(
		loss = DecisionTree.util.entropy,
		min_samples_leaf = 1,
		min_purity_increase = 0.01,
		min_loss_at_leaf = 0.6,
	)
]
# TODO add parameter: allow relationAll at all levels? Maybe it must be part of the relations... I don't know
modal_args = (
	n_subrelations = x -> ceil(sqrt(x)),
	# n_subrelations = x -> ceil(x/2),

	# initCondition = DecisionTree.startAtCenter,
	# initCondition = DecisionTree._startAtWorld(ModalLogic.Interval2D((1,3),(3,4))),
	initCondition = DecisionTree.startWithRelationAll,
	
	# ontology = getIntervalOntologyOfDim(Val(2)),
	# ontology = Ontology(ModalLogic.Interval2D,setdiff(Set(ModalLogic.RCC8Relations),Set([ModalLogic.Topo_PO]))),
	# ontology = Ontology(ModalLogic.Interval2D,[ModalLogic._IA2DRel(i,j) for j in [ModalLogic.IA_O,ModalLogic.IA_Oi] for i in [ModalLogic.IA_O,ModalLogic.IA_Oi]]),
	ontology = getIntervalOntologyOfDim(Val(1)),
	# ontology = Ontology(ModalLogic.Interval,[ModalLogic.Topo_PO]), # TODO fix error thrown here
	# ontology = getIntervalRCC8OntologyOfDim(Val(1)),
	# ontology = getIntervalRCC8OntologyOfDim(Val(2)),
	# ontology = getIntervalRCC5OntologyOfDim(Val(2)),

	# ontology=Ontology(ModalLogic.Interval2D,ModalLogic.AbstractRelation[]),
	useRelationId = true,
	# useRelationId = false,
	# useRelationAll = true,
	useRelationAll = false,
	# test_operators = [TestOpGeq],
	# test_operators = [TestOpLeq],
	# test_operators = [TestOpGeq, TestOpLeq],
	# test_operators = [TestOpGeq, TestOpLeq],
	# test_operators = [TestOpGeq, TestOpLeq, TestOpGeq_85, TestOpLeq_85],
	# test_operators = [TestOpGeq_70],
	test_operators = [TestOpGeq_70, TestOpLeq_70],
	# test_operators = [TestOpGeq_75, TestOpLeq_75],
	# test_operators = [TestOpGeq_85, TestOpLeq_85],
	# test_operators = [TestOpGeq_75],
	# rng = my_rng,
	# rng = DecisionTree.mk_rng(123),
)

loss = DecisionTree.util.entropy
# the minimum number of samples each leaf needs to have
min_samples_leaf = 1
# minimum purity needed for a split
min_purity_increase = 0.01
# maximum purity allowed on a leaf
min_loss_at_leaf = 0.4

log_results_best_values = false
repeat_test = 5
log_file = "./results-find-best-values/results.csv"
dataset_number = 5

if length(ARGS) === 5
	min_samples_leaf = parse(Int64, ARGS[1])
	min_purity_increase = parse(Float64, ARGS[2])
	min_loss_at_leaf = parse(Float64, ARGS[3])
	dataset_number = parse(Int64, ARGS[4])
	log_file = ARGS[5]
	log_results_best_values = true
end

# Best values found for a single tree and forest
#min_samples_leaf = 1
#min_purity_increase = 0.01
#min_loss_at_leaf = 0.4

# log_level = Logging.Warn
log_level = DecisionTree.DTOverview
# log_level = DecisionTree.DTDebug

# timing_mode = :btime
timing_mode = :none
round_dataset_to_datatype = false
# round_dataset_to_datatype = UInt8


# n_instances = 1
n_instances = 100
# n_instances = 300
# n_instances = 500

# rng_i = DecisionTree.mk_rng(124)
rng_i = DecisionTree.mk_rng(1)
gammas_save_path = "./results-audio-scan/gammas"

dataset = SplatEduardDataset(dataset_number)

T = nothing
Tcm = nothing
F = nothing
Fcm = nothing

function log_to_file(
		filename,
		min_samples_leaf,
		min_purity_increase,
		min_loss_at_leaf,
		tree_overall_accuracy,
		tree_mean_accuracy,
		tree_kappa,
		forest_overall_accuracy,
		forest_mean_accuracy,
		forest_kappa,
		forest_oob_error
	)

    file = open(filename, "a+")

	write(file,
		string(min_samples_leaf) * "," *
		string(min_purity_increase) * "," *
		string(min_loss_at_leaf) * "," *
		string(round.(mean(tree_overall_accuracy).*100, digits=2)) * "," *
		string(round.(mean(tree_mean_accuracy).*100, digits=2)) * "," *
		string(round.(mean(tree_kappa).*100, digits=2)) * "," *
		string(round.(mean(forest_overall_accuracy).*100, digits=2)) * "," *
		string(round.(mean(forest_mean_accuracy).*100, digits=2)) * "," *
		string(round.(mean(forest_kappa).*100, digits=2)) * "," *
		string(round.(mean(forest_oob_error).*100, digits=2)) * "\n"
	)

	close(file)
end

if log_results_best_values
	tree_overall_accuracy = []
	tree_mean_accuracy = []
	tree_kappa = []
	forest_overall_accuracy = []
	forest_mean_accuracy = []
	forest_kappa = []
	forest_oob_error = []

	for i in 1:repeat_test

		global T, F, Tcm, Fcm = testDataset(
			"Test",
			dataset,
			false;
			log_level                   =   log_level,
			round_dataset_to_datatype               =   round_dataset_to_datatype,
			forest_args                 =   forest_args,
			tree_args                   =   tree_args,
			modal_args                  =   modal_args,
			precompute_gammas           =   precompute_gammas,
			optimize_forest_computation =   optimize_forest_computation,
			rng                         =   rng
		);

		push!(tree_overall_accuracy, Tcm.overall_accuracy)
		push!(tree_mean_accuracy, Tcm.mean_accuracy)
		push!(tree_kappa, Tcm.kappa)
		push!(forest_overall_accuracy, Fcm.overall_accuracy)
		push!(forest_mean_accuracy, Fcm.mean_accuracy)
		push!(forest_kappa, Fcm.kappa)
		push!(forest_oob_error, F.oob_error)
	end

	log_to_file(
		log_file,
		min_samples_leaf,
		min_purity_increase,
		min_loss_at_leaf,
		tree_overall_accuracy,
		tree_mean_accuracy,
		tree_kappa,
		forest_overall_accuracy,
		forest_mean_accuracy,
		forest_kappa,
		forest_oob_error
	)
else
	T, F, Tcm, Fcm = testDataset(
		"Test",
		dataset,
		false;
		log_level                   =   log_level,
		round_dataset_to_datatype               =   round_dataset_to_datatype,
		forest_args                 =   forest_args,
		tree_args                   =   tree_args,
		modal_args                  =   modal_args,
		gammas_save_path            =   gammas_save_path,
		rng                         =   rng
	);
end
