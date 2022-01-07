# A Tty GUI for editing dictionaries!

using DisplayStructure
const DS = DisplayStructure
using Terming
const T = Terming
using DataFrames
using CrystalInfoFramework

#== Model - View - Controller idea

The model contains the dictionary being edited, the view is simply
regenerated after every change to the model, and the rest is the
controller.
==#

#== Models

Currently the model is 
==#

mutable struct DictModel
    base_dict::DDLm_Dictionary
    cur_def::String
    cur_attribute::String
    cur_val::Vector{Any}
    att_index::Int64
    ref_dic::Union{DDLm_Dictionary,Nothing}
end

DictModel(ddlm_dict,ref_dic) = begin
    all_defs = collect(keys(ddlm_dict))
    start_name = length(all_defs) > 0 ? all_defs[1] : ""
    println("Starting def is $start_name")
    d = DictModel(ddlm_dict,start_name,
                  "_definition.id",["?"],1,ref_dic)
    d.cur_val = val_for_att(d)
    return d
end

# The current definition is updated with the new value
update_model!(d,new_val) = begin
    println("Was $(d.cur_val)")
    update_dict!(d.base_dict,d.cur_def,d.cur_attribute,d.cur_val[d.att_index],new_val)
    d.cur_val = val_for_att(d)
    @assert d.cur_val[d.att_index] == new_val
    println("Now $(d.cur_val)")
end

possible_values(d) = begin
    try
        return d.ref_dic[d.cur_attribute][:enumeration_set].state
    catch
        return []
    end
end

val_for_att(d) = begin
    attr = d.cur_attribute
    cat,obj = split(attr,".")
    cat = Symbol(cat[2:end])
    info = d.base_dict[d.cur_def]
    if haskey(info,cat) && obj in names(info[cat])
        att_val = info[cat][!,obj]
    else
        att_val = ["?"]
    end
    return att_val
end

next_def(d) = begin
    all_defs = sort!(collect(keys(d.base_dict)))
    cur_index = findnext(isequal(d.cur_def),all_defs,1)
    if cur_index != length(all_defs)
        d.cur_def = all_defs[cur_index+1]
        d.att_index = 1
        d.cur_val= val_for_att(d)
    end
    true
end

back_def(d) = begin
    all_defs = sort!(collect(keys(d.base_dict)))
    cur_index = findnext(isequal(d.cur_def),all_defs,1)
    if cur_index != 1
        d.cur_def = all_defs[cur_index-1]
        d.att_index = 1
        d.cur_val = val_for_att(d)
    end
    true
end

"""

Make a new definition that is a copy of the current
definition with the object id changed to xxx
"""
make_new_def!(d) = begin
    old_def = d.base_dict[d.cur_def]
    new_def_name = "_"*old_def[:name].category_id[]*"."*"xxx"
    old_def[:name].object_id = ["xxx"]
    old_def[:definition].id = [new_def_name]
    d.base_dict = add_definition(d.base_dict,old_def)
    d.cur_def = new_def_name
    true
end

"""
Remove a definition
"""
delete_def!(d) = begin
    all_keys = sort!(collect(keys(d.base_dict)))
    if length(all_keys) == 1 return false end  #can't delete final def
    cur_pos = indexin([d.cur_def],all_keys)[]
    delete!(d.base_dict,d.cur_def)
    if cur_pos == 1 d.cur_def = all_keys[2] else d.cur_def = all_keys[cur_pos-1] end
    true
end

set_attr(d,attr) = begin
    if attr != ""
        d.cur_attribute = attr
        d.att_index = 1
        d.cur_val = val_for_att(d)
    end
    true
end

step_forward(d) = begin
    if length(d.cur_val) >= d.att_index+1
        d.att_index += 1
    end
    true 
end

step_back(d) = begin
    if d.att_index > 1
        d.att_index -= 1
    end
    true
end

# Actually change the definition

change_fwd(d) = begin
    if !isnothing(d.ref_dic)
        poss = possible_values(d)
        cur_index = indexin([d.cur_val[d.att_index]],poss)[]
        if cur_index + 1 <= length(poss)
            update_model!(d,poss[cur_index+1])
        end
    end
    true
end

change_bwd(d) = begin
    if !isnothing(d.ref_dic)
        poss = possible_values(d)
        cur_index = indexin([d.cur_val[d.att_index]],poss)[]
        if cur_index - 1 >= 1
            update_model!(d,poss[cur_index-1])
        end
    end
    true
end

#== Views

A simple view that simply takes the key information of the model
and presents it in a text ui.

==#

"""
     Display definition for `title` contained in `info`, with
     value at `index` for `attr` contained in editing pane.

     Somewhat clunky as it redoes the view every time, but we
     could consider an additional method that just updates the
     various elements in `ds`.
"""
gen_view(d::DictModel) = begin
    h,w = T.displaysize()
    ds = DS.DisplayStack()
    title = d.cur_def
    info = d.base_dict[title]
    attr = d.cur_attribute
    val = d.cur_val[d.att_index]
    push!(ds, :full_def => DS.Panel(title,[h-6,w],[1,1]))
    push!(ds, :attr => DS.Panel(attr,[5,w],[h-6,1]))
    # Show definition
    def_lines = prepare_def(title,info,lines=h-6)
    push!(ds, :base => DS.Label(def_lines,[2,2]))
    # Show attribute value
    push!(ds, :attribute => DS.Label(val,[h-5,2]))
    push!(ds, :instructions => DS.Label("(q) Quit (f) next def (b) prev def (c) category (o) object (n) new (x) delete (h) help" ,[h,5]))
    return ds
end

prepare_def(title,info;start=1,lines=20) = begin
    strbuf = IOBuffer()
    CrystalInfoFramework.show_one_def(strbuf,title,info)
    full = String(take!(strbuf))
    # drop first start lines
    start_char = 1
    lines = 1
    so_far = findnext("\n",full,start_char)
    while so_far != nothing
        so_far = so_far[]
        lines = lines + 1
        if lines < start start_char = so_far end
        if lines >= start + lines return full[start_char:so_far-1] end
        so_far = findnext("\n",full,so_far+1)
    end
    return full[start_char:end]     
end

# Return a bit of val suitable for display in the provided room
display_length(val,width) = begin
    val = strip(val)
    first_line = findnext('\n',val,1)
    if first_line != nothing
        val = val[1:first_line]
    end
    if length(val) > width return val[1:width-3]*"..." else return val end
end


## Controls

init_term() = begin
    T.raw!(true)
    T.alt_screen(true)
    T.cshow(false)
    T.clear()
end

reset_term() = begin
    T.raw!(false)
    T.alt_screen(false)
    T.cshow(true)
end


add_ref_dic(d::DictModel,ref_dic) = begin
    d.ref_dic = ref_dic
end

handle_quit() = begin
    keep_running = false
    T.cmove_line_last()
    T.println("\nShutting down")
    return keep_running
end

# Select a new attribute to work on 
att_select(f_ch,sec_ch) = begin
    if f_ch == "d"
        if sec_ch == "t"
            return "_description.text"
        elseif sec_ch == "c"
            return "_definition.class"
        end
    elseif f_ch == "t"
        if sec_ch == "s"
            return "_type.source"
        elseif sec_ch == "p"
            return "_type.purpose"
        elseif sec_ch == "c"
            return "_type.container"
        elseif sec_ch == "o"
            return "_type.contents"
        end
    end
    return ""
end

# Update the view based on the model
update(d::DictModel) = begin
    v = gen_view(d)
    DS.render(v)
end

handle_event(d::DictModel) = begin
    is_running = true
    options_list = possible_values(d)
    while is_running
        sequence = T.read_stream()
        event = T.parse_sequence(sequence)
        if sequence == "q"
            is_running = handle_quit()
        elseif sequence == "f"
            next_def(d) && update(d)
        elseif sequence == "b"
            back_def(d) && update(d)
        elseif sequence == "c"
            set_attr(d,"_name.category_id") && update(d)
        elseif sequence == "o"
            set_attr(d,"_name.object_id") && update(d)
        elseif sequence == "s"
            set_attr(d,"_enumeration_set.state") && update(d)
        elseif sequence == "e"
            handle_edit_event(d) && update(d)
        elseif sequence == "n"
            make_new_def!(d) && update(d)
        elseif sequence == "x"
            delete_def!(d) && update(d)
        # double-letter sequences for attributes
        elseif sequence in("d","t")
            second_let = T.read_stream()
            if second_let == "q" continue end
            set_attr(d,att_select(sequence,second_let)) && update(d)
        elseif event == T.KeyPressedEvent(T.RIGHT)
            step_forward(d) && update(d)
        elseif event == T.KeyPressedEvent(T.LEFT)
            step_back(d) && update(d)
        # fast editing for enumerated states
        elseif event == T.KeyPressedEvent(T.UP)
            change_bwd(d) && update(d)
        elseif event == T.KeyPressedEvent(T.DOWN)
            change_fwd(d) && update(d)
        end
    end
end

handle_edit_event(d::DictModel) = begin
    edit_mode = true
    options_list = possible_values(d)
    while edit_mode
        sequence = T.read_stream()
        if sequence == "\e"
            edit_mode = false
        end
    end
    return true
end

Base.run(start_dict::DDLm_Dictionary;ref_dict=nothing) = begin
    init_term()
    start_model = DictModel(start_dict,ref_dict)
    view = gen_view(start_model)
    DS.render(view)
    handle_event(start_model)
    reset_term()
    return
end

