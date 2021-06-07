# A Linter for DDLm dictionaries
using CrystalInfoFramework,Printf

using Lerche   #for our transformer

struct Linter <: Visitor_Recursive
end

print_err(line,text;err_code=000) = begin
    @printf "%6d: rule %5s: %s\n" line err_code text
end

check_column(token::Token,proper,rule_no) = begin
    if token.column != proper
        print_err(token.line,"$token should begin at $proper, begins at $(token.column)",err_code=rule_no)
    end
end

"""
    check_text_indent(val,indent,err_code)

Check that the multi-line value `val` contains `indent` spaces at the beginning of
each new line. If not, the appropriate `err_code` is provided.
"""
check_text_indent(val,indent,err_code) = begin
    if get_delimiter(val) == "\n;"
        if length(val.children[1].children) <= 2
            println("WARNING: blank semicolon field at line $(get_line(val))")
            return
        end
        for lt in val.children[1].children[2:(end-1)]
            line = String(traverse_to_value(lt))
            if match(r"^\s*\S+",line) == nothing
                # check for stray whitespace
                if length(line) > 1
                    print_err(get_line(lt),"Extra whitespace at beginning of blank line '$line'",err_code="2.1.9")
                    return
                end
            end
            start = match(r"^\s+",line)
            if start == nothing || length(start.match) < indent 
                print_err(get_line(lt),"Indent too small for '$line', should be at least $indent",err_code=err_code)
            end
        end
    elseif get_delimiter(val) in ["'''","\"\"\""]
        for (i,l) in enumerate(eachmatch(r"^\s*"m,traverse_to_value(val)))
            if i == 1 continue end
            if length(l.match) < indent
                print_err(get_line(val)+(i-1),"Indent too small for '$(l.match)', should be at least $indent",err_code=err_code)
            end
        end
    end
end

check_column(t::Tree,proper,rule_no) = check_column(t.children[1],proper,rule_no)

get_delimiter(value::Tree) = begin
    if value.data == "data_value" return get_delimiter(value.children[1]) end
    if value.data == "semi_string" return "\n;" end
    if value.data == "list" return "[" end
    if value.data == "table" return "{" end
    get_delimiter(traverse_to_value(value))
end

get_delimiter(value::Token) = begin
    if length(value) > 6
        if value[1:3] == "'''" return "'''" end
        if value[1:3] == "\"\"\"" return "\"\"\"" end
    end
    if value[1] == '\'' return "'" end
    if value[1] == '\"' return "\"" end
    return ""
end

get_delimiter_with_val(v) = begin
    delimiter = get_delimiter(v)
    if delimiter in ("[","{","\n;") return delimiter,v end
    value = traverse_to_value(v)
    del_len = length(delimiter)
    return delimiter,value[1+del_len:(end-del_len)]
end

traverse_to_value(tv::Tree) = begin
    if length(tv.children) == 1 return traverse_to_value(tv.children[1])
    else
        throw(error("Cannot find unique single value for $tv"))
    end
end

traverse_to_value(tv::Token) = tv

get_line(t::Tree) = get_line(t.children[1])
get_column(t::Tree) = get_column(t.children[1])
get_end_column(t::Tree) = get_end_column(t.children[end])
get_last_line(t::Tree) = get_last_line(t.children[end])
get_line(t::Token) = if t.type_ == "START_SC_LINE" t.line + 1 else t.line end
get_last_line(t::Token) = t.end_line
get_column(t::Token) = if t.type_ == "START_SC_LINE" 1 else t.column end
get_end_column(t::Token) = t.end_column

get_width(t::Token) = begin
    if t.line != t.end_line return line_length+1 end
    return t.end_column - t.column
end

get_width(t::Tree) = begin
    first_line = get_line(t)
    last_line = get_last_line(t)
    if get_line(t) != get_last_line(t) return line_length+1 end
    width = get_end_column(t) - get_column(t)
    if width <= 0 throw(error("Bad width for $t, $width")) end
    return width
end

@rule loop(l::Linter,tree) = begin
    check_column(tree.children[1],text_indent+1,"3.2.2")  #loop keyword
    args = tree.children
    # count data names
    boundary = findfirst(x->!isa(x,Lerche.Token),args)
    name_list = args[2:boundary-1]
    num_names = length(name_list)
    value_list = args[boundary:end]
    nrows,m = divrem(length(value_list),num_names)
    if m!=0
        print_err(name_list[1].line,"Number of values in loop is not a multiple of number of looped names",err_code="CIF")
    end
    if nrows == 1
        print_err(name_list[1].line,"Loop should be presented as key-value pairs: only one packet",err_code="3.2.1")
        return
    end
    # check consistent delimiters
    delims = check_loop_delimiters(name_list,value_list)
    # check proper layout
    check_loop_layout(name_list,value_list,delims)
    check_loop_text_indent(name_list,value_list,delims)
end

check_loop_delimiters(name_list,value_list) = begin
    num_names = length(name_list)
    best_delimiters = fill("",num_names)
    seen_triple = fill(false,num_names)
    seen_single = fill(false,num_names)
    nrows = div(length(value_list),num_names)
    delims = Array{Union{Nothing,String}}(undef,num_names)
    for n in 1:num_names
        delims[n],bare = get_delimiter_with_val(value_list[n])
        if !(delims[n] in ("[","{","\n;"))
             best_delimiters[n],_ = which_delimiter(bare)
             seen_triple[n] = occursin("\"\"\"",bare)
             seen_single[n] = occursin("\"",bare)
        else best_delimiters[n] = delims[n] end
    end
    for r in 2:nrows
        for n in 1:num_names
            #println("Checking $(value_list[(r-1)*num_names + n])")
            new_delimiter,bare = get_delimiter_with_val(value_list[(r-1)*num_names + n])
            if new_delimiter != delims[n]
                print_err(name_list[1].line,"Inconsistent delimiters for $(name_list[n]), seen $(delims[n]) and $new_delimiter",err_code="2.1.13")
            end
            if !(new_delimiter in ("[","{","\n;"))
                seen_triple[n] = seen_triple[n] || occursin("\"\"\"",bare)
                seen_single[n] = seen_single[n] || occursin("\"",bare)
                best_delimiters[n] = choose_best_delimiter(best_delimiters[n],which_delimiter(bare)[1],seen_triple[n],seen_single[n])
            end
        end
    end
    # Now check that these are the best delimiters
    for n in 1:num_names
        if delims[n] != best_delimiters[n]
            print_err(name_list[n].line,"Non-optimal delimiters for $(name_list[n]), should be \"$(best_delimiters[n])\"",err_code="2.1")
        end
    end
    return delims   #for use later
end

# Decide which delimiter is best of the proposed ones, given
# that we have seen triple quotes or single quotes
choose_best_delimiter(old_best,suggested,triple,single) = begin
    if old_best == "\n;" return old_best end
    prec = ("\n;","\"\"\"","'''","\"","'","")
    if findfirst(x->x==suggested,prec) < findfirst(x->x==old_best,prec)
        if suggested == "\"\"\"" && triple return "\n;"
        elseif suggested == "\"" && single return "'''"
        else return suggested end
    end
    return old_best
end

"""
    check_loop_layout(name_list,value_list,delims)

Check the alignment and spacing of the loop values
"""
check_loop_layout(name_list,value_list,delims) = begin
    num_names = length(name_list)
    for i in 1:num_names
        check_column(name_list[i],text_indent + loop_indent + 1,"3.2.3")
    end
    col_align = [get_column(x) for x in value_list[1:num_names]]
    # Check columns on a single line
    if num_names > 1
        diffs = col_align[2:end] - col_align[1:(end-1)]
        col = argmin(diffs)
        if diffs[col]<2 && get_line(value_list[col+1]) == get_line(value_list[col])
            print_err(get_line(value_list[col]),"Columns separated by less than 2 spaces",err_code="3.2.6")
        end
    end
    nrows = div(length(value_list),num_names)
    colwidths = fill(0,num_names)
    for n in 0:(nrows-1)
        for p in 1:num_names
            # check start of first value in packet
            my_value = value_list[n*num_names + p]
            if p == 1 && my_value.children[1].data != "semi_string"
                check_column(my_value,loop_align,"3.2.5")
            end
            # check first value comes after new line
            if n > 1 && p == 1
                if get_line(my_value) == get_line(value_list[n*num_names])
                    print_err(get_line(my_value), "First value in packet is not on new line",err_code="3.2.4")
                end
            end
            # check that all column line up
            if get_column(my_value) != col_align[p]
                print_err(get_line(my_value),"Column $p is misaligned:expected $(col_align[p]), got $(get_column(my_value))",err_code="3.2.10")
            end
            # accumulate values for column length
            colwidths[p] = max(get_width(my_value), colwidths[p])
        end
    end
    # Now check for ideal spacing
    if num_names == 1 return end
    ideal_steps,ideal_lines = calc_ideal_spacing(colwidths)
    #println("Ideal layout $ideal_steps, $ideal_lines")
    for i in 1:num_names
        if (colwidths[i] > line_length - loop_step) && !(delims[i] in ["\n;","[","{"])
            print_err(get_line(value_list[1]),"Delimiter for column $i should be semicolons",err_code="3.2.8")
        end
        if col_align[i] != ideal_steps[i] && !(delims[i] == "\n;")
            print_err(get_line(value_list[1]),"Column $i should start at $(ideal_steps[i]), saw $(col_align[i])",err_code="3.2.8,9")
        end
    end
end

check_loop_text_indent(name_list,value_list,delims) = begin
    indent = text_indent + loop_indent + 1
    num_names = length(name_list)
    nrows = div(length(value_list),num_names)
    for n in 0:(nrows-1)
        for p in 1:num_names
            val = value_list[n*num_names + p]
            if get_delimiter(val) in ("\n;","'''","\"\"\"")
                check_text_indent(val,indent,"3.2.7")
            end
        end
    end
end

@rule scalar_item(l::Linter,tree) = begin
    name = tree.children[1]
    check_column(name,text_indent+1,"3.1.1")
    val = tree.children[2]
    if val.children[1].data in ["quoted_string","bare"]
        check_delimiter(val)
    end
    delim = get_delimiter(val)
    if delim in ["'","\"",nothing,"[","{"]
        if name.line == get_line(val) 
            check_column(val,value_col,"3.1.2")
        else
            if get_width(val) <= line_length - value_col + 1
                printerr(get_line(val),"Value should appear on same line as data name",err_code="3.1.2")
            end
            if !(delim in ["[","{"])
                check_column(val,value_indent,"3.1.3")
            else
                check_column(val,value_col,"2.4.1")
            end
        end
    elseif delim in ["'''","\"\"\"","\\n;"]
        check_text_indent(val,text_indent,"2.1.9")
    end
end

check_delimiter(value) = begin
    value = traverse_to_value(value)
    quotechar = ""
    if value.type_ == "SINGLE_QUOTE_DATA_VALUE"
        quotechar = value[1:1]
        test_val = value[2:end-1]
    elseif value.type_ == "TRIPLE_QUOTE_DATA_VALUE"
        quotechar = value[1:3]
        test_val = value[4:end-4]
    else
        quotechar = ""
        test_val = value
    end
    best_delimiter,rule_no = which_delimiter(test_val)
    if best_delimiter != quotechar
        printval = value[1:min(length(value),20)]
        if length(printval) > 20 printval = printval*"..." end
        print_err(value.line,"Incorrect delimiters for $(printval): should be `$best_delimiter`",err_code=rule_no)
    end
end

@rule dblock(l::Linter,tree) = begin
    # check space after header
    line_diff = get_line(tree.children[2]) - get_line(tree.children[1])
    if line_diff == 1
        print_err(tree.children[2].line,"No blank line after data block header",err_code="4.1.5")
    end
    for i in 3:length(tree.children)
        c = tree.children[i]
        if c.data == "save_frame"
            line_diff = get_line(tree.children[i]) - get_line(tree.children[i-1])
            if line_diff == 1
                print_err(get_line(c),"No blank line before save frame header",err_code="4.3.1")
            end
        end
    end 
end

@rule save_frame(l::Linter,tree) = begin
    if get_line(tree.children[2]) < get_line(tree.children[1])+2
        print_err(get_line(tree.children[2]),"No blank line after save frame header",err_code="4.3.1")
    end
    if get_line(tree.children[end]) < get_line(tree.children[end-1])+2
        print_err(get_line(tree.children[end]),"No blank line before save frame end",err_code="4.3.1")
    end
end

# Non-grammar based checks

check_line_properties(fulltext) = begin
    double_lines = findall(r"\n\n\n",fulltext)
    for d in double_lines
        print_err(count(r"\n",fulltext[1:d.start]),"Double blank lines",err_code="1.4")
    end
    as_lines = collect(enumerate(split(fulltext,"\n")))
    line_lengths = map(x->(x[1],length(x[2])),as_lines)
    bad = filter(x->x[2]>80,line_lengths)
    if length(bad) > 0
        for (n,b) in bad
            print_err(n,"Line too long: $b characters",err_code="1.1")
        end
    end
    trailing = filter(x->length(x[2])>0 && x[2][end] == ' ',as_lines)
    for (n,b) in trailing
        print_err(n,"Trailing whitespace",err_code="1.3")
    end
end

check_first_space(fulltext) = begin
    finder = r"^(#(.+)\n)+\n\s*data_"m
    if match(finder,fulltext) == nothing
        print_err(1,"Data block is not preceded by optional comment and single blank line",err_code="4.1.3")
    end
end

check_last_char(fulltext) = begin
    if fulltext[end] != '\n'
        print_err(0,"Final character is not newline",err_code="4.1.4")
    end
end

lint_report(filename) = begin
    fulltext = read(filename,String)
    if occursin("\t",fulltext)
        println("Tabs found, please remove. Indent warnings may be incorrect")
    end
    check_line_properties(fulltext)
    check_first_space(fulltext)
    check_last_char(fulltext)
    ptree = Lerche.parse(CrystalInfoFramework.cif2_parser,fulltext,start="input")
    l = Linter()
    Lerche.visit(l,ptree)
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 1
        println("Usage: julia linter.jl <dictionary file>")
    else
        filename = ARGS[1]
        lint_report(filename)
    end
end
