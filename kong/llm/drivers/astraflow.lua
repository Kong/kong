-- Astraflow (by UCloud) is an OpenAI-compatible AI model aggregation platform
-- supporting 200+ models. Because its API is fully OpenAI-compatible, this driver
-- simply delegates all request/response handling to the OpenAI driver.
--
-- Global endpoint : https://api-us-ca.umodelverse.ai/v1  (env: ASTRAFLOW_API_KEY)
-- China endpoint  : https://api.modelverse.cn/v1         (env: ASTRAFLOW_CN_API_KEY)
-- Website         : https://astraflow.ucloud-global.com  (global)
--                   https://astraflow.ucloud.cn          (China)
return require("kong.llm.drivers.openai")
