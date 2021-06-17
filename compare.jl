# Compare two dictionaries, producing a report
using CrystalInfoFramework,DataFrames

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
report_missing_attrs(defa,defb,name,cat,ref_dic;ignore=[]) = begin
    if haskey(defa,cat)
        adef = defa[cat]
        if haskey(defb,cat)
            bdef = defb[cat]
            compare_loops(adef,bdef,name,cat,ref_dic,ignore=ignore)
        else
            println("$cat is missing from $name in second dictionary")
            println("First dictionary has $adef")
        end
        
    end
end

compare_loops(loop1,loop2,name,cat,ref_dic;ignore=[],wspace=false) = begin
    if nrow(loop1) != nrow(loop2)
        println("$cat has different number of rows for $name")
    end
    if nrow(loop1) == 0 return end
    # check columns
    ignorance = [String(x[end]) for x in ignore if first(x) == cat]
    anames = names(loop1)
    bnames = names(loop2)
    do_not_have = setdiff(anames,bnames,ignorance,["master_id","__object_id","__blockname"])
    if length(do_not_have) > 0
        println("$name: missing $do_not_have")
    end
    common = setdiff(intersect(anames,bnames),ignorance,["master_id","__object_id","__blockname"])
    # println("$cat")
    # loop and check values
    if nrow(loop1) > 1
        catkeys = get_keys_for_cat(ref_dic,"$cat")
        catobjs = Symbol.([find_object(ref_dic,x) for x in catkeys])
        nonmatch = check_matching_rows(loop1,loop2,catobjs,wspace)
        if nrow(nonmatch) > 0
            println("The following rows do not have matching keys for $cat:")
            println("$nonmatch")
        end
    end
    # now check all
    nonmatch = check_matching_rows(loop1,loop2,common,wspace)
    #println("Checked $common for $cat")
    if nrow(nonmatch) > 0
        println("The following rows have at least one mismatched value for $cat:")
        println("$nonmatch")
    end
end

check_matching_rows(dfa,dfb,keylist,wspace) = begin
    #println("Checking rows $keylist")
    if !wspace
        dfa = remove_wspace(dfa)
        dfb = remove_wspace(dfb)
    end
    test = antijoin(dfa,dfb;on=keylist,validate=(false,true))
    return test
end

remove_wspace(df) = begin
    for n in propertynames(df)
        df[:,n] = map(x->replace(x,r"[\n \t]+"m=>""),df[!,n])
    end
    return df
end

report_diffs(source_lang,dics;wspace=false) = begin
    if source_lang == "ddl2"
        ref_dic = DDL2_Dictionary(ddl2_ref_dic)
        dica,dicb = DDL2_Dictionary.(dics)
        test_categories = ddl2_test_categories
        ignore = ddl2_ignore
    else
        dica,dicb = DDLm_Dictionary.(dics, ignore_imports=true)
        ref_dic = DDLm_Dictionary(ddlm_ref_dic)
        test_categories = Symbol.(get_categories(ref_dic))
        ignore = []
    end
    println("Testing following categories:")
    println("$test_categories")
    difa,_ = find_missing_defs(dica,dicb)
    if length(difa) > 0
        println("Warning: missing definitions for $difa")
    end
    for one_def in sort(collect(keys(dica)))
        println("\n#=== $one_def ===#\n")
        if one_def in difa
            println("$one_def missing from second dictionary")
            continue
        end
        defa = dica[one_def]
        defb = dicb[one_def]
        for one_cat in test_categories
            report_missing_attrs(defa,defb,one_def,one_cat,ref_dic,ignore=ignore)
        end
    end
    # Check top level
    toplevela = dica[get_dic_name(dica)]
    toplevelb = dicb[get_dic_name(dicb)]
    println("\n=============\n\n Top level categories \n")
    for one_cat in keys(toplevela)
        if nrow(toplevela[one_cat]) == 0 continue end
        println("\n#=== $one_cat ===#\n")
        if !(one_cat in keys(toplevelb)) || nrow(toplevelb[one_cat]) == 0
            println("$one_cat is missing from second dictionary")
            continue
        end
        compare_loops(toplevela[one_cat],toplevelb[one_cat],"toplevel",one_cat,ref_dic,ignore=ignore,wspace=wspace)
    end      
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 4
        println("""
Usage: julia $(basename(PROGRAM_FILE)) <lang> <ws> <dictionary1> <dictionary2> 
where <lang> is the language in which both dictionaries are written: either "ddl2" 
or "ddlm". If <ws> is 'false', whitespace differences are ignored. """)
        exit()
    end
    source_lang = ARGS[1]
    wspace = parse(Bool,ARGS[2])
    dics = (ARGS[3],ARGS[4])
    report_diffs(source_lang,dics,wspace=wspace)
end
