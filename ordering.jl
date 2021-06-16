# Check the ordering of items in a DDLm dictionary matches the order
# prescribed by the style guide.

get_atts(a) = begin
    cat = String(a.first)
    atts = map(x->"_"*cat*"."*"$x",String.(a.second))
end

get_att_order(a) = begin
    order = []
    for cat in a
        append!(order,get_atts(cat))
    end
    return order
end

const atts_as_strings = get_att_order(ddlm_attribute_order)
const toplevel_strings = get_att_order(ddlm_toplevel_order)

mutable struct OrderCheck <: Visitor_Recursive
    seen_items::Array{String,1}
    seen_defs::Array{String,1}
    top_level::Array{String,1}
    cat_info::Array{Tuple{String,String},1}
    this_def::String
    this_parent::String
end

OrderCheck() = OrderCheck([],[],[],[],"","")

@rule scalar_item(oc::OrderCheck,tree) = begin
    push!(oc.seen_items,tree.children[1])
    if tree.children[1] == "_definition.id"
        oc.this_def = lowercase(traverse_to_value(tree.children[2]))
    elseif tree.children[1] == "_name.category_id"
        oc.this_parent = lowercase(traverse_to_value(tree.children[2]))
    elseif tree.children[1] == "_definition.class"
        class = traverse_to_value(tree.children[2])
        if class == "Head" && length(oc.seen_defs) != 0
            print_err(get_line(tree),"Head category should be the first definition",err_code="4.1.7")
        end
    end
end

@rule loop(oc::OrderCheck,tree) = begin
    n = 1
    boundary = findfirst(x-> !isa(x,Lerche.Token),tree.children)
    append!(oc.seen_items,tree.children[2:boundary-1])
end

@rule save_frame(oc::OrderCheck,tree) = begin
    check_order(atts_as_strings,oc.seen_items,"4.3.4",get_line(tree))
    cats = map(x->to_cat_obj(x)[1],oc.seen_items)
    if "import_details" in cats
        print_err(get_line(tree),"No import_details attributes should be used",err_code="4.3.3")
    end
    if !(oc.this_parent in oc.seen_defs) && length(oc.seen_defs) > 0 #Head is first
        print_err(get_line(tree),"Definition for child item $(oc.this_def) comes before category $(oc.this_parent)",err_code="4.1.8")
        #println("Seen $(oc.seen_defs)")
    end
    if oc.this_def != ""
        push!(oc.seen_defs,oc.this_def)
        push!(oc.cat_info,(oc.this_def,oc.this_parent))
    end
    # Make sure this item's category is the most recently seen, if it is a data name
    if occursin(".",oc.this_def)
        previous_cat = findlast(x->!occursin(".",x),oc.seen_defs)
        if lowercase(oc.seen_defs[previous_cat]) != oc.this_parent
            print_err(get_line(tree),"Definition for data name $(oc.this_def) is not grouped after parent category $(oc.this_parent)",err_code="4.1.8")
        end
    end
    oc.this_def = ""
end

@rule block_content(oc::OrderCheck,tree) = begin
    if tree.children[1].data == "data"
        append!(oc.top_level,oc.seen_items)
    end
    oc.seen_items = []
end

@rule dblock(oc::OrderCheck,tree) = begin
    check_order(toplevel_strings,oc.top_level,"4.2.1",get_line(tree))
    # check that looped items are after save frames
    saves_seen = false
    for b in tree.children[2]
        if b.data == "save_frame"
            saves_seen = true
            continue
        end
        if b.data == "data" && saves_seen
            if b.children[2].children[1].data != "loop"
                print_err(get_line(b.children[2].children[1]),"Non-looped top level items appear after save frames",err_code="4.2.2")
            end
        end
    end
    check_def_order(oc.cat_info)
end

to_cat_obj(v) = begin
    c,o = split(v,".")
    return lowercase(c[2:end]),lowercase(o)
end

check_order(right,observed,err_code,line) = begin
    known = filter(x->x in right,observed)
    checked = filter(x->x in observed,right)
    unknown = setdiff(observed,right)
    if length(unknown) > 0
        println("WARNING: unknown attributes $unknown")
    end
    if known != checked
        print_err(line,"Order of items in definition incorrect:",err_code=err_code)
        @printf "\n%-30s%-30s\n" "Actual" "Expected"
        for i in 1:minimum(length,[known,checked])
            @printf "%-30s%-30s\n" known[i] checked[i]
        end
        println()
    end
end

check_def_order(cat_tuples) = begin
    def_order = lowercase.([x[1] for x in cat_tuples])
    all_cats = unique!(filter(x-> !occursin(".",x),def_order))
    for one_cat in all_cats
        children = filter(x->x[2] == one_cat && x in all_cats,cat_tuples)
        children = [x[1] for x in children]
        if sort(children) != children
            print_err(0,"Child categories of category $one_cat not in alphabetical order", err_code="4.1.9")
            for (s,c) in zip(sort(children),children)
                @printf "%-30s%-30s\n" s c
            end
        end
        children = filter(x->x[2] == one_cat && !(x in all_cats),cat_tuples)
        children = [x[1] for x in children]
        if sort(children) != children
            print_err(0,"Child data names of category $one_cat not in alphabetical order", err_code="4.1.8")
            for (s,c) in zip(sort(children),children)
                @printf "%-30s%-30s\n" s c
            end
        end
    end
end

