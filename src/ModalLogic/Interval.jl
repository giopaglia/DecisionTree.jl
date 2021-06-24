

struct Interval <: AbstractWorld
	x :: Integer
	y :: Integer
	# TODO check x<y but only in debug mode.  && x<=N, y<=N ?
	# Interval(x,y) = x>0 && y>0 && x < y ? new(x,y) : error("Can't instantiate Interval(x={$x},y={$y})")
	Interval(w::Interval) = new(w.x,w.y)
	Interval(x::Integer,y::Integer) = new(x,y)
	Interval((x,y)::Tuple{Integer,Integer}) = new(x,y)
	Interval(::_emptyWorld) = new(-1,0)
	Interval(::_firstWorld) = new(1,2)
	Interval(::_centeredWorld, X::Integer) = new(div(X,2)+1,div(X,2)+1+1+(isodd(X) ? 0 : 1))
end

show(io::IO, w::Interval) = begin
	print(io, "(")
	print(io, w.x)
	print(io, "−")
	print(io, w.y)
	print(io, ")")
end

print_world(w::Interval) = println("Interval [$(w.x),$(w.y)) ($(w.y-w.x) points)")

worldTypeDimensionality(::Type{Interval}) = 1
# worldTypeComplexity(::Type{Interval}) = 2
n_worlds(::Type{Interval}, channel_size::Tuple{Integer}) = div(channel_size[1]*(channel_size[1]+1),2)

inst_readWorld(w::Interval, instance::MatricialInstance{T,2}) where {T} = instance[w.x:w.y-1,:]

# Convenience function: enumerate intervals in a given range
enumPairsIn(a::Integer, b::Integer) =
	Iterators.filter((a)->a[1]<a[2], Iterators.product(a:b-1, a+1:b)) # TODO try to avoid filter maybe
enumShortPairsIn(a::Integer, b::Integer) =
	IterTools.imap((x)->(x,x+1), a:b-1)

enumAccReprAggr(f::Union{AttributeMinimumFeatureType,AttributeMaximumFeatureType}, a::Union{typeof(minimum),typeof(maximum)}, ::AbstractWorldSet{Interval}, r::_RelationGlob,  X::Integer) = IterTools.imap(Interval, enumShortPairsIn(1, X+1))
enumAccReprAggr(f::Union{AttributeMaximumFeatureType}, a::typeof(maximum), ::AbstractWorldSet{Interval}, r::_RelationGlob,  X::Integer) = Interval[Interval(1, X+1)  ]
enumAccReprAggr(f::Union{AttributeMinimumFeatureType}, a::typeof(minimum), ::AbstractWorldSet{Interval}, r::_RelationGlob,  X::Integer) = Interval[Interval(1, X+1)  ]

enumAccReprAggr(f::Union{AttributeSoftMinimumFeatureType,AttributeSoftMaximumFeatureType}, a::Union{typeof(minimum),typeof(maximum)}, ::AbstractWorldSet{Interval}, r::_RelationGlob,  X::Integer) = IterTools.imap(Interval, enumShortPairsIn(1, X+1))
enumAccReprAggr(f::Union{AttributeSoftMaximumFeatureType}, a::typeof(maximum), ::AbstractWorldSet{Interval}, r::_RelationGlob,  X::Integer) = Interval[Interval(1, X+1)  ]
enumAccReprAggr(f::Union{AttributeSoftMinimumFeatureType}, a::typeof(minimum), ::AbstractWorldSet{Interval}, r::_RelationGlob,  X::Integer) = Interval[Interval(1, X+1)  ]

enumAccBare(w::Interval, ::_RelationId, XYZ::Vararg{Integer,N}) where N = [(w.x, w.y)]
enumAccessibles(S::Union{Interval,AbstractWorldSet{Interval}}, r::_RelationGlob, X::Integer) =
	IterTools.imap(Interval, enumPairsIn(1, X+1))


################################################################################
################################################################################
################################################################################

# needed for GAMMAS

yieldReprs(test_operator::_TestOpGeq, repr::_ReprMax{Interval},  channel::MatricialChannel{T,1}) where {T} =
	reverse(extrema(ch_readWorld(repr.w, channel)))::NTuple{2,T}
yieldReprs(test_operator::_TestOpGeq, repr::_ReprMin{Interval},  channel::MatricialChannel{T,1}) where {T} =
	extrema(ch_readWorld(repr.w, channel))::NTuple{2,T}
yieldReprs(test_operator::_TestOpGeq, repr::_ReprVal{Interval},  channel::MatricialChannel{T,1}) where {T} =
	(channel[repr.w.x],channel[repr.w.x])::NTuple{2,T}
yieldReprs(test_operator::_TestOpGeq, repr::_ReprNone{Interval}, channel::MatricialChannel{T,1}) where {T} =
	(typemin(T),typemax(T))::NTuple{2,T}

yieldRepr(test_operator::Union{_TestOpGeq,_TestOpLeq}, repr::_ReprMax{Interval},  channel::MatricialChannel{T,1}) where {T} =
	maximum(ch_readWorld(repr.w, channel))::T
yieldRepr(test_operator::Union{_TestOpGeq,_TestOpLeq}, repr::_ReprMin{Interval},  channel::MatricialChannel{T,1}) where {T} =
	minimum(ch_readWorld(repr.w, channel))::T
yieldRepr(test_operator::Union{_TestOpGeq,_TestOpLeq}, repr::_ReprVal{Interval},  channel::MatricialChannel{T,1}) where {T} =
	channel[repr.w.x]::T
yieldRepr(test_operator::_TestOpGeq, repr::_ReprNone{Interval}, channel::MatricialChannel{T,1}) where {T} =
	typemin(T)::T
yieldRepr(test_operator::_TestOpLeq, repr::_ReprNone{Interval}, channel::MatricialChannel{T,1}) where {T} =
	typemax(T)::T

enumAccRepr(test_operator::_TestOpGeq, w::Interval, ::_RelationGlob, X::Integer) = _ReprMax(Interval(1,X+1))
enumAccRepr(test_operator::_TestOpLeq, w::Interval, ::_RelationGlob, X::Integer) = _ReprMin(Interval(1,X+1))

# TODO optimize relationGlob
computeModalThresholdDual(test_operator::_TestOpGeq, w::Interval, r::R where R<:AbstractRelation, channel::MatricialChannel{T,1}) where {T} =
	yieldReprs(test_operator, enumAccRepr(test_operator, w, r, size(channel)...), channel)
computeModalThreshold(test_operator::Union{_TestOpGeq,_TestOpLeq}, w::Interval, r::R where R<:AbstractRelation, channel::MatricialChannel{T,1}) where {T} =
	yieldRepr(test_operator, enumAccRepr(test_operator, w, r, size(channel)...), channel)

# TODO optimize relationGlob?
# computeModalThresholdDual(test_operator::_TestOpGeq, w::Interval, ::_RelationGlob, channel::MatricialChannel{T,1}) where {T} = begin
# 	# X = length(channel)
# 	# println("Check!")
# 	# println(test_operator)
# 	# println(w)
# 	# println(relation)
# 	# println(channel)
# 	# println(computePropositionalThresholdDual(test_operator, Interval(1,X+1), channel))
# 	# readline()
# 	# computePropositionalThresholdDual(test_operator, Interval(1,X+1), channel)
# 	reverse(extrema(channel))
# end
# computeModalThreshold(test_operator::_TestOpGeq, w::Interval, ::_RelationGlob, channel::MatricialChannel{T,1}) where {T} = begin
# 	# TODO optimize this by replacing readworld with channel[1:X]...
# 	# X = length(channel)
# 	# maximum(ch_readWorld(Interval(1,X+1),channel))
# 	maximum(channel)
# end
# computeModalThreshold(test_operator::_TestOpLeq, w::Interval, ::_RelationGlob, channel::MatricialChannel{T,1}) where {T} = begin
# 	# TODO optimize this by replacing readworld with channel[1:X]...
# 	# X = length(channel)
# 	# minimum(ch_readWorld(Interval(1,X+1),channel))
# 	minimum(channel)
# end
	
ch_readWorld(w::Interval, channel::MatricialChannel{T,1}) where {T} = channel[w.x:w.y-1]
