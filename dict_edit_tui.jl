# A Tty GUI for editing dictionaries!

using DisplayStructure
const DS = DisplayStructure
using Terming
const T = Terming
using DataFrames
using CrystalInfoFramework
using Dates

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
    edit_val::String
    edit_pos::Int64
    message::String
    ref_dic::Union{DDLm_Dictionary,Nothing}
end

const base_help = "(q) Quit (f) next def (b) prev def (c) category (o) object (n) new (x) delete (h) help (k) keys"
const edit_help = "EDIT MODE (esc) leave"


DictModel(ddlm_dict,ref_dic) = begin
    all_defs = collect(keys(ddlm_dict))
    start_name = length(all_defs) > 0 ? all_defs[1] : ""
    println("Starting def is $start_name")
    d = DictModel(ddlm_dict,start_name,
                  "_definition.id",["?"],1,"",1,
                  base_help,ref_dic)
    d.cur_val = val_for_att(d)
    return d
end

# The current definition is updated with the new value
update_model!(d,new_val) = begin
    update_dict!(d.base_dict,d.cur_def,d.cur_attribute,d.cur_val[d.att_index],new_val)
    d.cur_val = val_for_att(d)
    @assert d.cur_val[d.att_index] == new_val
    auto_changes!(d)
end

auto_changes!(d) = begin
    if d.cur_attribute in ("_name.object_id","_name.category_id")
        if d.base_dict[d.cur_def][:definition].class[] == "Head"
            # cat / obj same for head definition
            changed_val = get_attribute(d.base_dict,d.cur_def,d.cur_attribute)[]
            update_dict!(d.base_dict,d.cur_def,"_name.category_id",changed_val)
            update_dict!(d.base_dict,d.cur_def,"_name.object_id",changed_val)
        end
        cat = d.base_dict[d.cur_def][:name].category_id[]
        obj = d.base_dict[d.cur_def][:name].object_id[]
        if is_category(d.base_dict,d.cur_def)
            new_def = obj
        else
            new_def = "_"*cat*"."*obj
        end
        update_dict!(d.base_dict,d.cur_def,"_definition.id",new_def)
        d.cur_def = new_def
    end
    # This should be done right at the end
    #today = Dates.format(Dates.now(),"yyyy-mm-dd")
    #update_dict!(d.base_dict,d.cur_def,"_definition.update",today)
end

update_model!(d) = begin
    update_model!(d,d.edit_val)
end

possible_values(d) = begin
    if d.cur_attribute == "_name.category_id"
        return get_categories(d.base_dict)
    end
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
    cur_index = findnext(isequal(lowercase(d.cur_def)),all_defs,1)
    if cur_index != length(all_defs)
        d.cur_def = all_defs[cur_index+1]
        d.att_index = 1
        d.cur_val= val_for_att(d)
    end
    true
end

back_def(d) = begin
    all_defs = sort!(collect(keys(d.base_dict)))
    cur_index = findnext(isequal(lowercase(d.cur_def)),all_defs,1)
    if cur_index != 1
        d.cur_def = all_defs[cur_index-1]
        d.att_index = 1
        d.cur_val = val_for_att(d)
    end
    true
end

## For editing

start_edit(d) = begin
    d.edit_val = strip(d.cur_val[d.att_index])
    d.edit_pos = length(d.edit_val)+1
    d.message = edit_help
    true
end

move_left(d) = d.edit_pos = d.edit_pos > 1 ? d.edit_pos-1 : d.edit_pos
move_right(d) = d.edit_pos = d.edit_pos <= length(d.edit_val) ? d.edit_pos+1 : d.edit_pos

delete_char(d) = begin
    if length(d.edit_val) > 0 && d.edit_pos > 0
        if d.edit_pos > length(d.edit_val)
            d.edit_val = d.edit_val[1:end-1]
        else
            d.edit_val = d.edit_val[1:d.edit_pos-2]*d.edit_val[d.edit_pos:end]
        end
    end
    move_left(d)
    true
end

insert_char(d,char) = begin
    pos = d.edit_pos
    d.edit_val = d.edit_val[1:pos-1]*char*d.edit_val[pos:end]
    move_right(d)
    true
end

finish_edit(d) = begin
    update_model!(d)
    d.edit_val = ""
    d.message = base_help
end

"""

Make a new definition that is a copy of the current
definition with the object id changed.
"""
make_new_def!(d) = begin
    old_def = d.base_dict[d.cur_def]
    new_def_name = "_"*old_def[:name].category_id[]*"."*old_def[:name].object_id[]*"_new"
    old_def[:name].object_id = ["xxx"]
    old_def[:definition].id = [new_def_name]
    old_def[:definition].update = [Dates.format(Dates.now(),"yyyy-mm-dd")]
    old_def[:description].text = ["Please edit me"]
    add_definition!(d.base_dict,old_def)
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
        if isnothing(cur_index) cur_index = 0 end #bad value
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
        if isnothing(cur_index) cur_index = 2 end
        if cur_index - 1 >= 1
            update_model!(d,poss[cur_index-1])
        end
    end
    true
end

#TODO: fix all dates for correctness
write_out(d,outfile) = begin
    f = open(outfile,"w")
    show(f,MIME("text/cif"),d.base_dict)
    close(f)
    d.message = "Written to $outfile"
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
    push!(ds, :instructions => DS.Label(d.message ,[h,5]))
    if d.edit_val == ""
        push!(ds, :attribute => DS.Label(val,[h-5,2]))
    else
        push!(ds, :attribute => DS.Label(d.edit_val,[h-5,2]))
    end
    return ds
end

# Should be added to DisplayStructure
Base.setindex!(ds::DisplayStack,v,k) = ds.elements[k] = v

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

# the help screen

const help_text = """

""" 

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
        elseif sec_ch == "s"
            return "_definition.scope"
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
    if d.edit_val != ""
        h,w = T.displaysize()
        T.cshow(true)
        T.cmove(h-5,d.edit_pos+1)
    end
end

handle_event(d::DictModel,name::String) = begin
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
            set_attr(d,"_name.object_id") && handle_edit_event(d) && update(d)
        elseif sequence == "s"
            set_attr(d,"_enumeration_set.state") && update(d)
        elseif sequence == "e"
            handle_edit_event(d) && update(d)
        elseif sequence == "k"
            set_attr(d,"_category_key.name") && update(d)
        elseif sequence == "n"
            make_new_def!(d) && update(d)
        elseif sequence == "x"
            delete_def!(d) && update(d)
        elseif sequence == "w"
            write_out(d,name) && update(d)
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
    start_edit(d)
    update(d)
    while edit_mode
        sequence = T.read_stream()
        event = T.parse_sequence(sequence)
        if sequence == "\e"
            edit_mode = false
        elseif event == T.KeyPressedEvent(T.BACKSPACE)
            delete_char(d) && update(d)
        elseif event == T.KeyPressedEvent(T.DELETE)
            delete_char(d) && update(d)
        elseif event == T.KeyPressedEvent(T.RIGHT)
            move_right(d); update(d)
        elseif event == T.KeyPressedEvent(T.LEFT)
            move_left(d);  update(d)
        else # insert character
            insert_char(d,sequence)
            update(d)
        end
    end
    finish_edit(d)
    update(d)
    return true
end

Base.run(start_dict::DDLm_Dictionary;ref_dict=nothing,out_name="") = begin
    init_term()
    start_model = DictModel(start_dict,ref_dict)
    view = gen_view(start_model)
    DS.render(view)
    handle_event(start_model,out_name)
    reset_term()
    return start_model.base_dict
end

blank_text = """
#\\#CIF_2.0
###################################################################
#                                                                 #
#           Starting dictionary                                   #
#                                                                 #
###################################################################
data_starting

_dictionary.title     STARTING
_dictionary.class     Instance
_dictionary.version   0.0.1
_dictionary.date      $(Dates.format(Dates.now(),"yyyy-mm-dd"))
_dictionary.ddl_conformance 4.1.0
_description.text
;
    This is a blank starting dictionary. This text should be edited
    to reflect the true purpose of the dictionary
;

save_BLANK

    _definition.id                BLANK
    _definition.scope             Category
    _definition.class             Head
    _definition.update            $(Dates.format(Dates.now(),"yyyy-mm-dd"))
    _description.text
;
    This category is the top category. It should be renamed above
    and below.
;
    _name.category_id             BLANK
    _name.object_id               BLANK

save_

"""

# Create a dictionary from nothing
create_run(out_name::String;ref_dict=nothing) = begin
    as_cif = Cif(blank_text)
    as_dic = DDLm_Dictionary(as_cif)
    return run(as_dic,ref_dict=ref_dict,out_name=out_name)
end
