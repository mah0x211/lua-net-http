std = "max"
include_files = {
    "http.lua",
    "lib/*.lua",
    "spec/*_spec.lua",
}
files["spec/*_spec.lua"] = {
    std = "+busted",
}
