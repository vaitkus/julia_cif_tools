# Check correct output of default values

mutable struct DefaultCheck <: Visitor_Recursive
    ref_dic::DDLm_Dictionary
    default_list::Dict{String,String}
    att_list::Array{String,1}
end

DefaultCheck(ref_dic::DDLm_Dictionary) = begin
    d = make_default_table(ref_dic)
    DefaultCheck(ref_dic,d,[])
end

make_default_table(d::DDLm_Dictionary) = begin
    deftab = Dict{String,String}()
    for k in keys(d)
        # no toplevel skipping!
        if :category_id in propertynames(d[k][:name]) &&
            d[k][:name].category_id[] in ("dictionary","dictionary_valid","dictionary_audit")
            continue
        end
        q = get_default(d,k)
        if !ismissing(q)
            if is_set_category(d,q)
                deftab[k] = q
            else
                println("Checking category for $k")
                c = find_category(d,k)
                if !(k in get_keys_for_cat(d,c))
                    deftab[k] = q
                end
            end
        end
    end
    # Always include even default _type values:
    for t in ("_type.purpose","_type.source","_type.container","_type.contents")
        pop!(deftab,t,nothing)
    end
    return deftab
end

@rule scalar_item(dc::DefaultCheck,tree) = begin
    attribute = tree.children[1]
    push!(dc.att_list,lowercase(attribute))
    v = traverse_to_value(tree.children[2],firstok=true)
    if attribute in keys(dc.default_list) && dc.default_list[attribute] == v
        print_err(get_line(tree),"Default value for $attribute should not be output",err_code="3.1.6")
    end
end

# Just capture all of the attributes
@rule loop(dc::DefaultCheck,tree) = begin
    boundary = findfirst(x->!isa(x,Token),tree.children[2:end])
    name_list = lowercase.(String.(tree.children[2:boundary-1]))
    append!(dc.att_list,name_list)
end

@rule save_frame(dc::DefaultCheck,tree) = begin
    # Check that all category keys are present
    all_cats = unique(map(x->split(x,".")[1][2:end],dc.att_list))
    for a in all_cats
        internal_key = "_$a.master_id"
        if is_loop_category(dc.ref_dic,a)
            kn = lowercase.(get_keys_for_cat(dc.ref_dic,a))
            setdiff!(kn,[internal_key])
            if intersect(kn,dc.att_list) != kn
                not_there = setdiff(kn,dc.att_list)
                print_err(get_line(tree),"Missing key data name(s) $not_there for category $a",err_code="CIF")
            end
        end
    end
    dc.att_list = []
end
