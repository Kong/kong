"""
A list of wasm filters.
"""

WASM_FILTERS = [
    {
        "name": "proxy-wasm-rust-response-transformer",
        "repo": "Kong/proxy-wasm-rust-response-transformer",
        "tag": "0.1.2",
        "files": {
            "response_transformer.meta.json": "cf5e51e7118287000656def07ec42b2482d60e02966b72426beab3ea0c39302a",
            "response_transformer.wasm": "95429bf14878bc67b6f70a555f77e304b5f2b8f9ee77b49da99cbf4474c22046",
        },
    },
    # {
    #     "name": "datakit-filter",
    #     "repo": "Kong/datakit-filter",
    #     "tag": "0.1.0",
    #     "files": {
    #         "datakit_filter.meta.json": "cf5e51e7118287000656def07ec42b2482d60e02966b72426beab3ea0c39302a",
    #         "datakit_filter.wasm": "2d03b5e3fc076a6b1b786914107a9d38c6ece8fca886dcbb6b1dee82d18c0063",
    #     },
    # },
]

WASM_FILTERS_TARGETS = [
    [
        "@%s//file" % file
        for file in filter["files"].keys()
    ]
    for filter in WASM_FILTERS
][0]
