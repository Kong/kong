"""
A list of wasm filters.
"""

WASM_FILTERS = [
    {
        "name": "datakit-filter",
        "repo": "Kong/datakit",
        "tag": "0.3.1",
        "files": {
            "datakit.meta.json": "acd16448615ea23315e68d4516edd79135bae13469f7bf9129f7b1139cd2b873",
            "datakit.wasm": "c086e6fb36a6ed8c9ff3284805485c7280380469b6a556ccf7e5bc06edce27e7",
        },
    },
]

WASM_FILTERS_TARGETS = [
    "@%s-%s//file" % (filter["name"], file)
    for filter in WASM_FILTERS
    for file in filter["files"].keys()
]
