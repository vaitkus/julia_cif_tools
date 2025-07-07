# A CIF tool to rearrange blocks to conform to the provided specification
# of which Set categories should be split over blocks

# Specifications: Set categories that should be grouped together
using CrystalInfoFramework
using DataFrames
using ArgParse

"""
    Create a CIF file in which the contents of `infile` have been reorganised between
    data blocks according to `out_spec` using the relational structure defined in
    `ddl_dict`. If `audit_dataset`, repeat the contents of `audit_dataset` in every
    data block.
"""
reorganise(ddl_dict, infile; import_dir = "", outfile = stdout, out_spec = nothing, audit_dataset = true) = begin

    incif = Cif(infile)
    refdic = DDLm_Dictionary(ddl_dict)

    # Construct output blocks from a series of tuples containing Set category names

    block_ref = construct_blocks(out_spec, refdic, incif, audit_dataset)

    for one_block in keys(incif)

        @debug "== Now working on $one_block =="
        try
            distribute_data(refdic, incif[one_block], block_ref)
        catch
            @error "Error working on $one_block"
            throw(error("Failed to distribute data from $one_block"))
        end
    end

    for out_cif in block_ref
        show(outfile, MIME("text/cif"), out_cif)
    end

    return block_ref

end

"""
    construct_blocks(specification, dictionary, data)

Specification is a list of tuples, where each tuple contains Set category
names that should be grouped together. If specification is empty, all
non-singleton Set categories are separated.
"""
construct_blocks(spec, refdic, infile, audit_dataset; single_block = true) = begin

    # Initial information

    all_categories = unique(Iterators.flatten([ all_categories_in_block(b, refdic) for (_,b) in infile]))
    
    all_sets = intersect(get_set_categories(refdic), all_categories)
    gsg = generate_set_groups(refdic, all_categories)
    all_keyed_sets = filter(x -> size(refdic[x][:category_key], 1) == 1, all_sets)
    all_vals = collect_values.(Ref(infile), Ref(refdic), all_keyed_sets)
    lens = map(length, all_vals)
    ignore_cats = [x for (i,x) in enumerate(all_keyed_sets) if lens[i] == 0]
    single_cats = [x for (i,x) in enumerate(all_keyed_sets) if lens[1] == 1]
    full_cats = [x for x in all_sets if !(x in ignore_cats) && !(x in single_cats)]

    @debug "Finished initial survey of $(length(all_sets)) set categories" ignore_cats single_cats full_cats

    # Generate specification
    
    if isnothing(spec)
        spec = collect(keys(gsg))
    else
        sort!.(spec)
    end

    @debug "Specification" spec
    
    block_dict = Dict{Tuple, Cif}()
    if single_block
        block_dict[("_single",)] = Cif()
    end

    if audit_dataset
        all_ids = unique(collect(Iterators.flatten((b["_audit_dataset.id"] for (_,b) in infile))))
        @debug "All dataset ids:" all_ids
    end
    
    # Create blocks
    
    for one_block_spec in spec

        @debug "Now working on $one_block_spec"
        
        if length(intersect(one_block_spec, ignore_cats)) > 0 continue end
        if length(intersect(one_block_spec, single_cats)) > 0 && single_block continue end
        val_list = []
        for one_cat in one_block_spec

            @debug "Processing $one_cat"
            
            ix = indexin([one_cat], all_keyed_sets)
            if isnothing(ix[])
                throw(error("Category $one_cat in specification tuple $one_block_spec is not a Set category with a key"))
            end

            push!(val_list, all_vals[ix[]])

        end

        # Now create a block for all combinations. Note that one_cat will have
        # only one key data name as it is derived from all_keyed_sets

        block_dict[tuple(one_block_spec...)] = Cif()
        key_names = map( x -> get_keys_for_cat(refdic, x)[], one_block_spec)
        foreach(Iterators.product(val_list...)) do pr

            @debug "Key names $key_names, values are $pr"
            blockname = reduce(*, pr)
            b = CifBlock()
            block_dict[tuple(one_block_spec...)][blockname] = b
            for (kn, kv) in zip(key_names, pr)
                @debug "Setting $kn to $kv in $blockname"
                b[kn] = [kv]
            end

            if audit_dataset
                b["_audit_dataset.id"] = all_ids
            end
            
        end
        
    end

    return block_dict
end

"""
    Find all values for the key data name of `catname` in the
    entire Cif file (multiple data blocks).
"""
collect_values(cif_data, refdic, catname) = begin

    k = get_keys_for_cat(refdic, catname)
    if length(k) != 1
        throw(error("Not enough/too many keys for $catname ($k)"))
    end

    k = k[]

    values = []
    for cb in keys(cif_data)
        if haskey(cif_data[cb], k)
            append!(values, cif_data[cb][k])
        end
    end

    return unique(values)
end

"""
    Generate a table of which loop categories depend on which
    Set categories. Returned is a Dict indexed by a list of
    Set categories resolving to a tuple (keys, list of categories).
    `present` is a list of all categories actually present.
"""
generate_set_groups(d::DDLm_Dictionary, present) = begin

    multi_related = Dict{Tuple, Any}()

    # Find categories with links to Set categories

    gsc = filter( x -> is_set_category(d, x), present)
    append!(gsc, filter( x-> is_loop_category(d,x), present))
    for g in gsc
        cat_keys = get_keys_for_cat(d, g)
        if length(cat_keys) == 0 continue end

        @debug "Processing $g"
        
        final_keys = get_ultimate_link.(Ref(d), cat_keys)
        final_cats = sort!(find_category.(Ref(d), final_keys))

        # Set categories only

        filter!(x -> is_set_category(d, x), final_cats)
        if length(final_cats) > 0

            @debug "$g is related to $final_cats"

            fc = tuple(final_cats...)
            if haskey(multi_related, fc)
                push!(multi_related[fc][2], g)
            else
                all_keys = map(x -> get_keys_for_cat(d, x), final_cats)
                multi_related[fc] = (all_keys, [g])
            end
        end
        
    end

    return multi_related
end

"""
    Run through cif block cb, distributing data into the
    appropriate block of `block_ref`, which is a dictionary
    of CIF files.
"""
distribute_data(d::DDLm_Dictionary, cb::CifContainer, block_ref) = begin

    split_parent_child!(d, cb)   #Avoid ambiguity
    for (cat_list, ciffile) in block_ref
        for (bname, target_block) in ciffile
            for c in cat_list
                if c != "_single"
                    k = get_keys_for_cat(d, c)[]
                    kv = target_block[k][]
                else
                    k = nothing
                    kv = nothing
                end
                
                @debug "Filtering on $k = $kv"
                
                new_block = filter_on_value(d, cb, k, kv)
                if isnothing(new_block) continue end
                
                @debug "Found values, merging"
                merge_block!(target_block, new_block, d)
                    
            end
            
        end
    end
    
end

"""
    List all categories present in `cb`
"""
get_all_cats(d::DDLm_Dictionary, cb::CifContainer) = begin
    non_unique = map(collect(keys(cb))) do k
        b = find_category(d, k)
        isnothing(b) ? missing : b
    end
    unique(skipmissing(non_unique))
end

"""
    Return a new CifContainer where only those values corresponding to
    `value` for key `dataname` are present. Any categories not including
    key linked data names for `dataname` are ignored. `dataname` should
    be a `Set` key data name. If `dataname` is nothing, only those
    datanames that are not part of a Set-linked category are returned.
"""
filter_on_value(d::DDLm_Dictionary, cb::CifContainer, dataname, value) = begin

    if !is_set_category(d, find_category(d, dataname))
        throw(error("$dataname does not belong to a Set category"))
    end

    has_implicit_value = haskey(cb, dataname)

    if has_implicit_value
        implicit_value = cb[dataname][]
    end
    
    dnames = get_dataname_children(d, dataname)
    filter!( x -> x in get_keys_for_cat(d, find_category(d, x)), dnames)
    present = intersect(dnames, keys(cb))
    if length(present) == 0 return nothing end

    @debug "Have $present in block"
    # We may have assumed values in which case all values are returned.

    mask_names = has_implicit_value ? dnames : present
   
    # @debug "Names to mask on $value" mask_names
    
    newblock = CifBlock()
    for mn in mask_names
        
        curr_cat = find_category(d, mn) 
        have_names = intersect(get_names_in_cat(d, curr_cat), keys(cb))

        if length(have_names) == 0 continue end
        
        @debug "Present for $curr_cat" have_names
        
        # Treat differently depending on implicit values

        if has_implicit_value && !(mn in present)
            if implicit_value == value

                @debug "Using implicit value to bulk accept $curr_cat"
                for hn in have_names
                    newblock[hn] = cb[hn]
                end
            else
                continue
            end
        else
            @debug "Computing mask for $curr_cat using $mn"
            mask = map( x -> x == value, cb[mn])
            if !any(mask) continue end
            for hn in have_names
                if hn == mn && hn != dataname continue end   # implicit value now
                new_val = cb[hn][mask .== true]
                newblock[hn] = new_val
            end 
        end

        create_loop!(newblock, have_names)
    end

    return newblock
end

filter_on_value(d::DDLm_Dictionary, cb::CifContainer, dataname::Nothing, value) = begin

    # Return only non-Set-linked data names

    all_sets = get_set_categories(d)
    all_keyed_sets = filter(x -> size(d[x][:category_key], 1) == 1, all_sets)
    all_keys = [get_keys_for_cat(d, a)[] for a in all_keyed_sets]
    all_related_cats = []

    for ak in all_keys
        rel_cats = find_category.(Ref(d), get_linked_keys(d, ak))
        append!(all_related_cats, rel_cats)
    end

    unique!(all_related_cats)

    @debug "All set-related categories" all_related_cats

    @debug "Non-set-related categories" setdiff(get_categories(d), all_related_cats)

    newblock = CifBlock()
    
    # All unlooped names

    for unl in get_all_unlooped_names(cb)
        if !(find_category(d, unl) in all_related_cats)
            newblock[unl] = cb[unl]
        end
    end
    
    # Now work on all loops

    all_loops = CrystalInfoFramework.get_loop_names(cb)
    for al in all_loops
        cat = guess_category(pd, al)
        if !(cat in all_related_cats)

        # output this cat
            for one_name in al
                newblock[one_name] = cb[one_name]
            end

            create_loop!(newblock, al)
        end
    end

    return newblock

end


"""
    Return the names and values of Set id data names
that apply to the supplied category in `cb`.
"""
get_set_id_name_value(d::DDLm_Dictionary, category, cb::CifContainer) = begin
    all_keys = get_keys_for_cat(d, category)
    top_keys = get_ultimate_link.(Ref(d), all_keys)
    final_cats = find_category.(Ref(d), top_keys)
    filter!( x->is_set_category(d, x), final_cats)

    @debug "Operative set categories for $category are $final_cats"
    
    # Now find any values in this data block for each of the final set cats

    result = []
    for fs in final_cats
        vals = []
        top_key = get_keys_for_cat(d, fs)[]  #only one surely
        all_poss = get_dataname_children(d, top_key)
        for dname in all_poss
            if haskey(cb, dname)
                append!(vals, cb[dname])
            end
        end

        if length(vals) > 0
            push!(result, (fs, vals))
        end
    end

    return result
end

"""
    Make all data names canonical
"""
make_canonical!(d::DDLm_Dictionary, cb::CifContainer) = begin

    old_names = keys(cb)

    # Set up new names
    
    for on in old_names
        nn = find_name(d, on)
        if nn == on continue end
        rename!(cb, on, nn)
    end

end

"""
    Split parent/child categories completely, duplicating keys
    as necessary
"""
split_parent_child!(d::DDLm_Dictionary, cb::CifContainer) = begin

    cats_for_work = get_all_cats(d, cb)

    # Sign we need to split is that a data name from a child
    # category is present together with a parent category
    
    loop_children = filter(cats_for_work) do cfw
        parent_cat = get_parent_category(d, cfw)
        parent_cat in cats_for_work && is_loop_category(d, parent_cat)
    end

    @debug "Need to split out $loop_children"

    while length(loop_children) > 0
        nxt = pop!(loop_children)
        parent = get_parent_category(d, nxt)

        # Are both keys present?

        parent_keys = get_keys_for_cat(d, parent)
        child_keys = get_keys_for_cat(d, nxt)

        @debug "Now working on $nxt" parent_keys child_keys
        
        # The key values for the child categories are the same as the
        # parent categories

        @assert Set(get_linked_name.(Ref(d), child_keys)) == Set(parent_keys)

        # Record links

        temp_parent_keys = []
        for ck in child_keys
            pk = get_linked_name(d, ck)
            push!(temp_parent_keys, (ck, pk))
        end

        # Begin the loops
        
        for (c, p) in temp_parent_keys
            if haskey(cb, c)
                @debug "Category for $c already exists, not attempting split"
                break
            end

            if haskey(cb, p) && !haskey(cb, c)

                @debug "Populating child key $c from $p"
                
                cb[c] = cb[p]
                add_to_loop!(cb, first(CrystalInfoFramework.get_loop_names(cb, parent, d)), c)

            end
        end

        # Create the child loop
        create_loop!(cb, CrystalInfoFramework.get_loop_names(cb, nxt, d))
        
        parent_loop = get_loop(cb, parent_keys[1])
        @debug "Parent loop" parent_loop
    end

end

"""
   Merge parent/child categories into one loop
   DOES NOT WORK
"""
merge_parent_child!(d::DDLm_Dictionary, cb::CifContainer) = begin
    
    cats_for_work = get_all_cats(d, cb)
    loop_parents = filter(cats_for_work) do cfw
        is_loop_category(d, get_parent_category(d, cfw))
    end

    @debug "Need to merge $loop_parents"

    while length(loop_parents) > 0

        nxt = pop!(loop_parents)

        parent = get_parent_category(d, nxt)

        # Are both keys present

        parent_keys = get_keys_for_cat(d, parent)
        child_keys = get_keys_for_cat(d, nxt)

        @debug "Now working on $nxt" parent_keys child_keys
        

        # Algorithm: the key values for the top category are the union of
        # the keys for the sub categories

        @assert Set(get_linked_name.(Ref(d), child_keys)) == Set(parent_keys)

        # Record links

        temp_parent_keys = []
        for ck in child_keys
            pk = get_linked_name(d, ck)
            push!(temp_parent_keys, (ck, pk))
        end

        #old_parent_loop = get_loop(cb, parent_keys[1])
        #new_parent_df = outerjoin(start_dataframe, old_parent_loop, on = parent_keys)

        # Now merge in child section

        # Prepopulate if missing

        for (c, p) in temp_parent_keys
            if haskey(cb, p) && !haskey(cb, c)

                @debug "Populating child key $c from $p"
                
                cb[c] = cb[p]
                add_to_loop!(cb, first(CrystalInfoFramework.get_loop_names(cb, nxt, d)), c)
            end
        end
        
        child_loop = get_loop(cb, child_keys[1])
        parent_loop = get_loop(cb, parent_keys[1])
        @debug "Child loop" child_loop
        @debug "Parent loop" parent_loop

        # Drop data names that are not part of category

        select!(child_loop, Symbol.(CrystalInfoFramework.get_loop_names(cb, nxt, d)))
        select!(parent_loop, Symbol.(CrystalInfoFramework.get_loop_names(cb, parent, d; children = true)))
        @debug "Dict-restricted Child loop" child_loop
        @debug "Dict-restricted Parent loop" parent_loop

        key_spec = [ Symbol(x) => Symbol(y) for (y, x) in temp_parent_keys if haskey(cb, y) || haskey(cb, x)]

        @debug "Key spec for merging" key_spec

        new_parent_df = outerjoin(parent_loop, child_loop, on = key_spec)

        # Return to block

        for c in names(child_loop)
            @debug "Deleting $c"
            delete!(cb, c)
        end
        for p in names(new_parent_df)
            cb[p] = new_parent_df[:,p]
            @debug "Added $p"
        end

        create_loop!(cb, names(new_parent_df))

        @debug "Final loop" get_loop(cb, first(parent_keys))
 
    end
        
end

parse_spec_file(specfile) = begin

    l = readlines(specfile)
    m = map(x -> split.(lowercase(x)), l)
    filter!(x -> length(x) > 0 && x[1][1] != '#', m)

    @debug "Read in spec" m
    return m
end

parse_cmdline(d) = begin
    s = ArgParseSettings(d)
    @add_arg_table! s begin
        "dictname"
         help = "A CIF DDLm dictionary"
         required = true
        "infile"
         help = "A file whose blocks should be rearranged."
        required = true
        "--outfile", "-o"
        help = "Output file"
        required = false
        default = ""
        "--import-dir","-i"
        help = "Directory to search for imported files in. Default is the same directory as the dictionary"
        arg_type = String
        default = ""
        "--audit-dataset", "-a"
        help = "Include any values of `_audit_dataset.id` found in any data block in all data blocks"
        arg_type = Bool
        default = true
        required = false
        "--spec", "-s"
        help = "Specification file for reorganisation"
        arg_type = String
        default = ""
    end
    parse_args(s)
end

const explanatory_text = """
Redistribute data among blocks in the supplied CIF file.

CIF data blocks are slices out of a notional set of relational tables. These tables
can be sliced in different ways. This tool takes a collection of blocks and reslices
the underlying relational representation according to the specified requirements.

The specification file is a series of space-separated Set category
names. Data names from categories appearing on the same line will
always appear together, even if that would involve repeating
information.  Datanames not belonging to a Set category or Set-linked
category will be output in a single, separate data block.

"""

if abspath(PROGRAM_FILE) == @__FILE__
    parsed_args = parse_cmdline(explanatory_text)

    @debug "$parsed_args"

    if parsed_args["outfile"] == [""]
        outfile = stdout
    else
        outfile = open(parsed_args["outfile"],"w")
    end

    pas = parsed_args["spec"]
    if pas == ""
        spec = nothing
    else
        spec = parse_spec_file(pas)
    end
    
    reorganise(parsed_args["dictname"], parsed_args["infile"],
                 import_dir = parsed_args["import-dir"],
                 audit_dataset = parsed_args["audit-dataset"],
                 outfile = outfile, out_spec = spec)

    close(outfile)
end
