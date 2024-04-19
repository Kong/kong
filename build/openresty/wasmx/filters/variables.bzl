"""
A list of wasm filters.
"""

WASM_FILTERS = [
    {
        "name": "datakit-filter",
        "repo": "Kong/datakit-filter",
        "tag": "0.1.0",
        "files": {
            "datakit.meta.json": "b9f3b6d51d9566fae1a34c0e5c00f0d5ad5dc8f6ce7bf81931fd0be189de205d",
            "datakit.wasm": "a494c254915e222c3bd2b36944156680b4534bdadf438fb2143df9e0a4ef60ad",
        },
    },
]

WASM_FILTERS_TARGETS = [
    "@%s-%s//file" % (filter["name"], file)
    for filter in WASM_FILTERS
    for file in filter["files"].keys()
]
