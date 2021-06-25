
_default_table_file_name(type::String) = "$(type)_cached.csv"
_default_jld_file_name(type::String, hash::String) = string(type * "_" * hash * ".jld")

function _infos_to_dict(infos::NamedTuple)::Dict
    Dict([String(k) => v for (k,v) in zip(keys(infos),values(infos))])
end

function cached_obj_exists(type::String, common_cache_dir::String, hash::String)::Bool
	isdir(common_cache_dir) && isfile(common_cache_dir * "/" * _default_jld_file_name(type, hash))
end
cached_obj_exists(type::String, common_cache_dir::String, infos::Dict)::Bool = cached_obj_exists(type, common_cache_dir, get_hash_sha256(infos))
cached_obj_exists(type::String, common_cache_dir::String, infos::NamedTuple)::Bool = cached_obj_exists(type, common_cache_dir, _infos_to_dict(infos))

function cache_obj(type::String, common_cache_dir::String, obj::Any, hash::String; column_separator::String = ";")
	total_save_path = common_cache_dir * "/" * _default_jld_file_name(type, hash)
	mkpath(dirname(total_save_path))

    table_file = open(common_cache_dir * "/" * _default_table_file_name(type), "a+")
    if ! isfile(common_cache_dir * "/" * _default_table_file_name(type))
        write(table_file, string("TIMESTAMP$(column_separator)FILE NAME$(column_separator)\n"))
    end
	write(table_file, string(
            Dates.format(Dates.now(), "dd/mm/yyyy HH:MM:SS"), column_separator,
            _default_jld_file_name(type, hash), column_separator, "\n"))
	close(table_file)

	checkpoint_stdout("Saving $(type) to file $(total_save_path)...")
	JLD2.@save total_save_path obj
end
cache_obj(type::String, common_cache_dir::String, obj::Any, infos::Dict; kwargs...) = cache_obj(type, common_cache_dir, obj, get_hash_sha256(infos); kwargs...)
cache_obj(type::String, common_cache_dir::String, obj::Any, infos::NamedTuple; kwargs...) = cache_obj(type, common_cache_dir, obj, _infos_to_dict(infos))

function load_cached_obj(type::String, common_cache_dir::String, hash::String)
	total_load_path = common_cache_dir * "/" * _default_jld_file_name(type, hash)

	checkpoint_stdout("Loading $(type) from file $(total_load_path)...")
	JLD2.@load total_load_path obj

	obj
end
load_cached_obj(type::String, common_cache_dir::String, infos::NamedTuple) = load_cached_obj(type, common_cache_dir, _infos_to_dict(infos))
load_cached_obj(type::String, common_cache_dir::String, infos::Dict) = load_cached_obj(type, common_cache_dir, get_hash_sha256(infos))

macro cache(type, common_cache_dir, args, kwargs, compute_function)
	# TODO type check
	# hyigene
	type = esc(type)
	common_cache_dir = esc(common_cache_dir)
	args = esc(args)
	kwargs = esc(kwargs)
	compute_function = esc(compute_function)

	return quote
		hash = get_hash_sha256(($(args), _infos_to_dict($(kwargs))))
		if cached_obj_exists($(type), $(common_cache_dir), hash)
			load_cached_obj($(type), $(common_cache_dir), hash)
		else
			checkpoint_stdout("Computing $(type)...")
			value = $(compute_function)($(args)...; $(kwargs)...)
			cache_obj($(type), $(common_cache_dir), value, hash)
			value
		end
	end
end
macro cache(type, common_cache_dir, args, compute_function)
	# TODO type check
	# hyigene
	type = esc(type)
	common_cache_dir = esc(common_cache_dir)
	args = esc(args)
	compute_function = esc(compute_function)

	return quote
		hash = get_hash_sha256($(args))
		if cached_obj_exists($(type), $(common_cache_dir), hash)
			load_cached_obj($(type), $(common_cache_dir), hash)
		else
			checkpoint_stdout("Computing $(type)...")
			value = $(compute_function)($(args)...)
			cache_obj($(type), $(common_cache_dir), value, hash)
			value
		end
	end
end
