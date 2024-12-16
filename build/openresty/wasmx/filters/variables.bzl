"""
A list of wasm filters.
"""

WASM_FILTERS = []

WASM_FILTERS_TARGETS = [
    [
        "@%s//file" % file
        for file in filter["files"].keys()
    ]
    for filter in WASM_FILTERS
]
