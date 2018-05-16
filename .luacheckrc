std = "min"
include_files = {
    "lib/*.lua",
    "spec/*_spec.lua",
}
files["spec/*_spec.lua"] = {
    std = "+busted"
}
