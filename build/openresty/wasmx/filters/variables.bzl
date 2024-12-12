"""
A list of wasm filters.
"""

WASM_FILTERS = []

WASM_FILTERS_TARGETS = [
    "@%s-%s//file" % (filter["name"], file)
    for filter in WASM_FILTERS
    for file in filter["files"].keys()
]
