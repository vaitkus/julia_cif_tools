# Pretty print. We just use CrystalInfoFramework's facilities

using CrystalInfoFramework,FilePaths

pretty(infile,outfile) = begin
    i = DDLm_Dictionary(Cif(infile,native=true),ignore_imports=true)
    o = open(outfile,"w")
    show(o,MIME("text/cif"),i)
    close(o)
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 2
        println("Usage: julia pretty_print.jl <before> <after>")
        println("""
Format DDLm dictionary file <before> according to IUCr style guidelines. The
result is placed in <after>.""")
    else
        filename = ARGS[1]
        outname = ARGS[2]
        pretty(Path(filename),Path(outname))
    end
end
