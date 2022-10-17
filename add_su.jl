# Routines to add SU data names that are missing
# We rely on the "general_su" imported data for
# generic su values

using CrystalInfoFramework,Dates,DataFrames,FilePaths

add_su(filename,for_real) = begin
    dic = DDLm_Dictionary(filename,ignore_imports=true)
    full_dic = DDLm_Dictionary(filename) #grab the imported "Measurands"
    templ_dic = Cif(Path(joinpath(dirname(filename), "templ_attr.cif")))
    templ_block = get_frames(first(templ_dic).second)["general_su"]
    no_sus = collect_defs(full_dic)
    if !for_real return nothing,no_sus end
    latest = dic
    for one_def in no_sus
        println("Constructing $one_def")
        latest = construct_su_def(latest,one_def,full_dic,templ_block)
        CrystalInfoFramework.show_one_def(stdout,one_def*"_su",latest[one_def*"_su"])
    end
    return latest,no_sus
end

collect_defs(dic) = begin
    mm = filter_def((:type,:purpose),"Measurand",dic)
    mmdefs = mm[:definition].id
    sudefs = filter_def((:type,:purpose),"SU",dic)
    su_present = sudefs[:name].linked_item_id
    println("Following items have su:")
    for i in sort!(su_present) println("$i") end
    return setdiff(mmdefs,su_present,[find_head_category(dic)])
end

"""
    `full_dic` is the dictionary with all imports resolved,
so that we have access to the type information.
"""
construct_su_def(dic,data_name,full_dic,import_block) = begin
    # Add a row to the relevant tables
    md_def = full_dic[data_name]
    su_data_name = data_name*"_su"
    new_def = Dict{Symbol,DataFrame}()
    # Name
    new_def[:name] = DataFrame()
    new_def[:name].category_id = md_def[:name].category_id
    new_def[:name].object_id = [md_def[:name].object_id[]*"_su"]
    new_def[:name].linked_item_id = [data_name]
    # Definition
    new_def[:definition] = DataFrame()
    new_def[:definition].id = [su_data_name]
    new_def[:definition].update = ["$(today())"]
    # Description
    new_def[:description] = DataFrame()
    new_def[:description].text = ["Standard uncertainty of $data_name."]
    # Type
    # No need for type if it matches the general_su block
    if md_def[:type].container[] == import_block["_type.container"][]
        new_def[:import] = DataFrame()
        new_def[:import].get = [[Dict("save"=>"general_su","file"=>"templ_attr.cif")]]
    else
        new_def[:type] = DataFrame()
        new_def[:type].purpose = ["SU"]
        new_def[:type].source = ["Derived"]
        new_def[:type].container = md_def[:type].container
        new_def[:type].contents = md_def[:type].contents
    end
    if :dimension in propertynames(md_def[:type])
        new_def[:type].dimension = md_def[:type].dimension
    end
    # Units
    new_def[:units] = DataFrame()
    if :code in propertynames(md_def[:units])
        new_def[:units].code = md_def[:units].code
    end
    # And add methods *if* they are Definition for _units.code
    mm = filter(row->row.purpose == "Definition" &&
                occursin("_units.code",row.expression),md_def[:method])
    if nrow(mm) > 0
        new_def[:method] = mm
    end
    return add_definition!(dic,new_def)
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 1
        println("Usage: julia add_su.jl <dictionary file> <do_it>")
        println("""
<dictionary file> is the file to be checked. If <do_it> is present and
'true', an updated version of <dictionary file> is written to <dictionary file>.update_su
""")
    else
        fname = ARGS[1]
        if length(ARGS) >= 2 for_real = parse(Bool,ARGS[2]) else for_real = false end
        updated,added = add_su(fname,for_real)
        println("Total added definitions: $(length(added))")
        for k in sort!(added)
            println("$k")
        end
        println()
        w = open(fname*".update_su","w")
        show(w,MIME("text/cif"),updated)
        close(w)
    end
end
