# Pretty print. We just use CrystalInfoFramework's facilities

using CrystalInfoFramework, ArgParse

pretty(infile,outfile;refdic=nothing, expand=false) = begin
    ignore = expand ? :Full : :All
    i = DDLm_Dictionary(Cif(infile),ignore_imports=ignore)
    o = open(outfile,"w")
    
    # Capitalise

    make_cats_uppercase!(i)

    # Match capitalisation

    if refdic != nothing
        rr = DDLm_Dictionary(refdic)
        conform_capitals!(i,rr)
    end
    
    show(o,MIME("text/cif"),i)
    close(o)
end

parse_cmdline(d) = begin
    s = ArgParseSettings(d)
    @add_arg_table! s begin
        "before"
         help = "Input dictionary"
         required = true
        "after"
        help = "File to write pretty-printed dictionary to"
        required = true
        "-r","--refdic"
        help = "DDL reference dictionary. If absent, capitalisation will not be harmonised"
        required = false
        default = [nothing]
        nargs = 1
        "-e","--expand"
        help = "Expand import templates"
        nargs = 0
        required = false
        default = false
    end
    parse_args(s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    parsed_args = parse_cmdline("Pretty print DDLm dictionary to match DDLm style guide.")
    pretty(parsed_args["before"], parsed_args["after"], refdic=parsed_args["refdic"][], expand = parsed_args["expand"])
end
