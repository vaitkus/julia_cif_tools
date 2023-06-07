# Compare two dictionaries, producing a report
using CrystalInfoFramework,DataFrames,ArgParse

const ddl2_ref_dic = "ddl2_with_methods.dic"
const ddlm_ref_dic = "/home/jrh/COMCIFS/cif_core/ddl.dic"
#
# The DDL2 categories that we care about
#
const ddl2_test_categories = (:item_range,:item_default,:item,
                              :category,:category_key,
                              :category_group_list,
                              :sub_category,
                              :dictionary_history,
                              :item_type,
                              :item_linked,
                              :item_examples,
                              :item_enumeration,
                              :item_description,
                              :item_range,
                              :item_units,
                              :item_sub_category,
                              :item_units_list,
                              :dictionary,
                              :category_examples,
                              :category_description,
                              :item_type_list
                              )
const ddl2_ignore = ()
#    ((:item,:mandatory_code),(:category,:nx_mapping_details),
#                     (:category,:mandatory_code))
#
const result_counter = Dict{Symbol,Int}(:defs=>0,:loops=>0,:probs=>0)

print_err(s) = begin
    result_counter[:probs] += 1
    println(s)
end

# Find definitions that are present in one and not the other
#
find_missing_defs(dica,dicb) = begin
    a = lowercase.(keys(dica))
    b = lowercase.(keys(dicb))
    differenta = setdiff(a,b)
    differentb = setdiff(b,a)
    return differenta,differentb
end

#
# Find attributes in the definition in dica from cat that are missing or
# different in dicb
#
check_one_def(defa,defb,name,cat,ref_dic;kwargs...) = begin
    if haskey(defa,cat)
        adef = defa[cat]
        if haskey(defb,cat)
            bdef = defb[cat]
            compare_loops(adef,bdef,name,cat,ref_dic;kwargs...)
            result_counter[:loops] += 1
        else
            print_err("$cat is missing from $name in second dictionary\nFirst dictionary has $adef")
        end 
    end
end

compare_loops(loop1,loop2,name,cat,ref_dic;ignore=[],wspace=false,caseless=false) = begin
    if nrow(loop1) != nrow(loop2)
        print_err("$cat has different number of rows for $name")
    end
    if nrow(loop1) == 0 return end
    # check columns
    ignorance = [String(x[end]) for x in ignore if first(x) == cat]
    anames = names(loop1)
    bnames = names(loop2)
    do_not_have = setdiff(anames,bnames,ignorance,["master_id","__object_id","__blockname"])
    if length(do_not_have) > 0
        print_err("$name: missing $do_not_have")
    end
    common = setdiff(intersect(anames,bnames),ignorance,["master_id","__object_id","__blockname"])
    # println("$cat")
    # loop and check values
    if nrow(loop1) > 1
        catkeys = get_keys_for_cat(ref_dic,"$cat")
        catobjs = Symbol.([find_object(ref_dic,x) for x in catkeys])
        nonmatch = check_matching_rows(loop1,loop2,catobjs,wspace,caseless)
        if nrow(nonmatch) > 0
            print_err("The following rows do not have matching keys for $cat in $name:\n$nonmatch")
        end
    end
    # now check all
    nonmatch = check_matching_rows(loop1,loop2,common,wspace,caseless)
    #println("Checked $common for $cat")
    if nrow(nonmatch) > 0
        print_err("The following rows have at least one mismatched value for $cat in $name:\n$nonmatch")
    end
end

check_matching_rows(dfa,dfb,keylist,wspace,caseless) = begin
    #println("Checking rows $keylist")
    if wspace
        dfa = remove_wspace(dfa)
        dfb = remove_wspace(dfb)
    end
    if caseless
        dfa = make_lower(dfa)
        dfb = make_lower(dfb)
    end
    test = antijoin(dfa,dfb;on=keylist,validate=(false,true))
    return test
end

remove_wspace(df) = begin
    for n in propertynames(df)
        df[:,n] = map(df[!,n]) do x
            isnothing(x) ? x : replace(x,r"[\n \t]+"m=>"")
        end
    end
    return df
end

make_lower(df) = begin
    for n in propertynames(df)
        df[:,n] = map(df[!,n]) do x
            typeof(x) <: AbstractString ? lowercase(x) : x
        end
    end
    return df
end

report_diffs(source_lang,dics;ignore=(),kwargs...) = begin
    if source_lang == "ddl2"
        ref_dic = DDL2_Dictionary(ddl2_ref_dic)
        dica,dicb = DDL2_Dictionary.(dics)
        test_categories = ddl2_test_categories
        ignore = union(ignore, ddl2_ignore)
    else
        dica,dicb = DDLm_Dictionary.(dics, ignore_imports=:All)
        ref_dic = DDLm_Dictionary(ddlm_ref_dic)
        test_categories = Symbol.(get_categories(ref_dic))
    end
    println("Testing following categories:")
    println("$test_categories")
    println("Ignoring: $ignore")
    difa,_ = find_missing_defs(dica,dicb)
    if length(difa) > 0
        print_err("Warning: missing definitions for $difa")
    end
    for one_def in sort(collect(keys(dica)))
        result_counter[:defs] += 1
        if one_def in difa
            print_err("$one_def missing from second dictionary")
            continue
        end
        defa = dica[one_def]
        defb = dicb[one_def]
        for one_cat in test_categories
            check_one_def(defa,defb,one_def,one_cat,ref_dic;ignore=ignore,kwargs...)
        end
    end
    # Check top level
    toplevela = dica[get_dic_name(dica)]
    toplevelb = dicb[get_dic_name(dicb)]
    println("\n=============\n\n Top level categories \n")
    for one_cat in keys(toplevela)
        if nrow(toplevela[one_cat]) == 0 continue end
        if !(one_cat in keys(toplevelb)) || nrow(toplevelb[one_cat]) == 0
            print_err("$one_cat is missing from second dictionary")
            continue
        end
        compare_loops(toplevela[one_cat],toplevelb[one_cat],"toplevel",one_cat,ref_dic;ignore=ignore,kwargs...)
    end
    #
    println("Summary\n=======\n")
    println("Problems found: $(result_counter[:probs])")
    println("Definitions checked: $(result_counter[:defs])")
    println("Loops compared: $(result_counter[:loops])")
end

parse_cmdline() = begin
    s = ArgParseSettings()
    @add_arg_table! s begin
        "dictionary1"
          help = "First dictionary to compare"
          required = true
        "dictionary2"
          help = "Second dictionary to compare"
          required = true
        "-w"
          help = "Ignore whitespace differences"
          action = :store_true
        "-c"
          help = "Ignore case differences"
          action = :store_true
        "--lang"
          arg_type = String
          default = "ddlm"
          help = "Dictionary language: 'ddlm' or 'ddl2'"
        "--ignore"
         arg_type = String
        help = "Ignore differences for attribute _xxx.yyy"
        nargs = '*'
    end
    parse_args(s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    parsed_args = parse_cmdline()
    source_lang = parsed_args["lang"]
    wspace = parsed_args["w"]
    caseless = parsed_args["c"]
    println("$parsed_args")
    dics = (parsed_args["dictionary1"],parsed_args["dictionary2"])
    ignore = map(x->Symbol.(split(x[2:end],".")),parsed_args["ignore"])
    report_diffs(source_lang,dics,wspace=wspace,caseless=caseless,ignore=ignore)
end
