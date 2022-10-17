# Check capitalisation of data names and category attributes
#
# Some notes: 'distance_derived' is acceptable so a more complex
# construction to catch things like 'distance_DA_su' is required.
#
const proper_names = ("Wyckoff","Cartn","_H_M\$","_H_M_","_Hall",
                      "Schoenflies","Patterson","Seitz","Friedel",
                      "R_factor","F_calc","Fcalc","Flack","Fox","Cromer_Mann",
                      "Laue","Rogers","Bijvoet",
                      "F_complex","F_meas","F_squared","Rmerge","A_calc",
                      "B_calc","A_meas","B_meas","Bravais",
                      "B_equiv","U_equiv","B[_]*iso","U[_]*iso",
                      "matrix_B([_]|\$)","matrix_U([_]|\$)","U_[1-3]+","B_[1-3]+","Uij","Bij",
                      "UBij","av_R_","TIJ","_T_max","_T_min","F_000","RGB",
                      "^IT_","label_[ADH]","distance_[DAH]+(_|\$)","symmetry_[DAH]\$",
                      "angle_[DAH]+(_|\$)",
                      "Cambridge","units_Z","CAS\$","ISBN","CSD","Medline",
                      "ASTM","ISSN","^COD\$","NCA","^NH","MDF","NBS","PDB","PDF",
                      "_CCDC_","DOI\$","ORCID\$","IUCr\$","IUPAC\$",
                      "SMILES\$","InChI","_RMS","_Cu\$","_Mo\$","ADP",
                      "I_over_I","I_over_netI","I_net","R_Fsqd","^R_I_","Lp_factor",
                      "R_I_factor","I_over_suI","meas_F","_S_",
                      "^R\$","^RT\$","^T\$","^B\$","^Ro\$","EPINET","_IZA\$",
                      "RCSR","_SP\$","TOPOS\$","Voronoi","Stokes_I","Stokes_Q",
                      "Stokes_U","Stokes_V",

                      # Powder dictionary

                      "_wR_","_len_Q\$", "March-Dollase", "March_Dollase",

                      # rho_CIF

                      "^P[0-9]{2}", "^P[0-9]_[0-9]", "^Pc", "^Pv"
                      )

mutable struct CapitalCheck <: Visitor_Recursive
    iscat::Bool
    isfunc::Bool
    code_items::Array{String,1}
    enums::Dict{String,Array{String,1}}
end

CapitalCheck() = CapitalCheck(false,false,[],Dict())

CapitalCheck(d::DDLm_Dictionary) = begin
    code_items = list_code_defs(d)
    enum_items = get_enums(d)
    CapitalCheck(false,false,code_items,enum_items)
end

all_upper(s) = begin
    if all(isuppercase,s) return true end
    c = match(r"[^a-z]+",String(s))
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
            print_err(get_line(tree),"Category names should be uppercase in category definition for $v",err_code = "2.1.10")
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
    if attribute in cc.code_items && !(attribute in keys(cc.enums))
        v = traverse_to_value(tree.children[2],delims=false)
        if isletter(v[1]) && !isuppercase(v[1])
            print_err(get_line(tree),"Attribute values for $attribute should be capitalised",err_code="2.1.12")
        end
    end
    if attribute in keys(cc.enums)
        v = traverse_to_value(tree.children[2],firstok=true,delims=false)
        poss = cc.enums[attribute]
        if !(v in poss)
            print_err(get_line(tree),"Attribute value $v for $attribute does not follow that used in the reference dictionary",err_code="2.1.13")
        end
    end
end

@rule loop(cc::CapitalCheck,tree) = begin
    boundary = findfirst(x-> !isa(x,Lerche.Token),tree.children)
    dnames = String.(tree.children[2:boundary-1])
    for i in boundary:length(tree.children[boundary:end])
        dname = dnames[((i-boundary)%length(dnames))+1]
        if dname in keys(cc.enums)
            poss = cc.enums[dname]
            val = String(traverse_to_value(tree.children[i],firstok=true,delims=false))
            if !(val in poss)
                print_err(get_line(tree.children[i]),"Attribute value $val for $dname is not capitalised as in the reference dictionary", err_code="2.1.13")
            end
        end
    end
end

@rule save_frame(cc::CapitalCheck,tree) = begin
    if cc.iscat && !all_upper(tree.children[1][6:end])
        print_err(get_line(tree),"Save frame name is not all upper case for category definition",err_code = "4.3.1")
    end
    name = first(Lerche.find_pred(tree,x->x.children[1]=="_name.category_id"))
    object = first(Lerche.find_pred(tree,x->x.children[1]=="_name.object_id"))
    name = traverse_to_value(name.children[2])
    object = traverse_to_value(object.children[2])
    if cc.iscat && (!all_upper(name) || !all_upper(object))
        print_err(get_line(tree),"Save frame for $object does not have capitalised category names in _name.category_id or _name.object_id",err_code="2.1.10")
    end
    if !cc.iscat && !cc.isfunc && (!canonical_case(name) || !canonical_case(object))
        print_err(get_line(tree),"Save frame for $object does not have canonical case for category/object names $name/$object",err_code="2.1.11")
    end
    if cc.isfunc && (!isuppercase(object[1]) || occursin("_",object))
        print_err(get_line(tree),"Function name should be CamelCase",err_code="2.1.14")
    end
    cc.iscat = false
    cc.isfunc = false
end

canonical_case(name) = begin
    lname = lowercase(name)
    for pn in proper_names
        if match(Regex(lowercase(pn)),String(lname)) !== nothing
            if match(Regex(pn),String(name))=== nothing
                @debug "Expected $pn in $name"
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
