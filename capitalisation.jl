# Check capitalisation of data names and category attributes
#
const proper_names = ("Wyckoff","Cartn","_H_M\$","_H_M_","_Hall",
                      "Schoenflies","Patterson","Seitz","Friedel",
                      "R_factor","F_calc","Fcalc","Flack","Fox","Cromer_Mann",
                      "Laue","Rogers","Bijvoet",
                      "F_complex","F_meas","F_squared","Rmerge","A_calc",
                      "B_calc","A_meas","B_meas","Bravais",
                      "B_equiv","U_equiv","B[_]*iso","U[_]*iso",
                      "matrix_B\$","matrix_U\$","U_[1-3]+","B_[1-3]+","Uij","Bij",
                      "UBij","av_R_","TIJ","_T_max","_T_min","F_000","RGB",
                      "^IT_","label_[ADH]","distance_[DAH]+","symmetry_[DAH]\$",
                      "angle_[DAH]+(_|\$)",
                      "Cambridge","units_Z","CAS","ISBN","CSD","Medline",
                      "ASTM","ISSN","^COD\$","NCA","^NH","MDF","NBS","PDB","PDF",
                      "I_over_I","I_over_netI","I_net","R_Fsqd","^R_I_","Lp_factor",
                      "R_I_factor","I_over_suI","meas_F","_S_",
                      "^R\$","^RT\$","^T\$","^B\$","^Ro\$"
                      )

mutable struct CapitalCheck <: Visitor_Recursive
    iscat::Bool
    isfunc::Bool
    code_items::Array{String,1}
end

CapitalCheck() = CapitalCheck(false,false,[])

CapitalCheck(ref_dic::String) = begin
    d = DDLm_Dictionary(ref_dic)
    code_items = list_code_defs(d)
    CapitalCheck(false,code_items)
end

all_upper(s) = begin
    if all(isuppercase,s) return true end
    c = match(r"[A-Z_]+",String(s))
    c != nothing && length(c.match) == length(s)
end

all_lower(s) = begin
    if all(islowercase,s) return true end
    c = match(r"[^A-Z]+",String(s))
    c != nothing && length(c.match) == length(s)
end


@rule scalar_item(cc::CapitalCheck,tree) = begin
    attribute = tree.children[1]
    if attribute == "_definition.id"
        v = traverse_to_value(tree.children[2])
        if !occursin(".",v) && !all_upper(v)
            print_err(get_line(tree),"Category names should be uppercase in category definition for $v",err_code = "2.1.14")
        end
    end
    if attribute == "_definition.scope"
        v = traverse_to_value(tree.children[2])
        if v == "Category" cc.iscat = true end
    end
    if attribute == "_name.category_id"
        v = traverse_to_value(tree.children[2])
        if v == "function" cc.isfunc = true end
    end
    if attribute in cc.code_items
        v = traverse_to_value(tree.children[2])
        if isletter(v[1]) && !isuppercase(v[1])
            print_err(get_line(tree),"Attribute values for $attribute should be capitalised",err_code="2.1.16")
        end
    end
end

@rule save_frame(cc::CapitalCheck,tree) = begin
    name = first(Lerche.find_pred(tree,x->x.children[1]=="_name.category_id"))
    object = first(Lerche.find_pred(tree,x->x.children[1]=="_name.object_id"))
    name = traverse_to_value(name.children[2])
    object = traverse_to_value(object.children[2])
    if cc.iscat && (!all_upper(name) || !all_upper(object))
        print_err(get_line(tree),"Save frame for $object does not have capitalised category names in _name.category_id or _name.object_id",err_code="2.1.14")
    end
    if !cc.iscat && !cc.isfunc && (!canonical_case(name) || !canonical_case(object))
        print_err(get_line(tree),"Save frame for $object does not have canonical case for category/object names $name/$object",err_code="2.1.15")
    end
    if cc.isfunc && (!isuppercase(object[1]) || occursin("_",object))
        print_err(get_line(tree),"Function name should be CamelCase",err_code="2.1.17")
    end
    cc.iscat = false
    cc.isfunc = false
end

canonical_case(name) = begin
    lname = lowercase(name)
    for pn in proper_names
        if match(Regex(lowercase(pn)),String(lname)) !== nothing
            if match(Regex(pn),String(name))=== nothing
                println("Expected $pn in $name")
                return false
            else
                return true
            end
        end
    end
    if !all_lower(name) return false end
    return true
end

# Get all attributes that are code-valued

list_code_defs(d) = begin
    filter(collect(keys(d))) do x
        if :contents in propertynames(d[x][:type])
            d[x][:type].contents[] == "Code"
        else
            false
        end
    end
end
