# A very simple parser for import specifications. The import specification is
# assumed to be a list containing a single table with non-delimited string
# values and keys delimited by single quotes.

read_import_spec(t) = begin
    return Lerche.transform(Importer(),t)
end

struct Importer <: Transformer end

@rule data_value(im::Importer,args) = args[1]
    
@rule list(im::Importer,args) = begin
    return args[2]
end

@rule table(im::Importer,args) = begin
    return Dict(args[2:end-1])
end

@inline_rule table_entry(im::Importer,key,value) = begin
    return String(key[2:end-1])=>traverse_to_value(value,firstok=true)
end
