## Third party integration test - AWS

** Note: The third party integration test on AWS is a new workflow which is not yet in a good shape. The implementation and arrangement of this test is still under discussion and development, so the description in this README only represents the current situation and may change in the future.

The directory holds the integration test suite on a real AWS environment.

Github workflow is `.github/workflows/integration_test_on_aws.yml`.

This integration test now runs on the self hosted runner, which is a group of EC2 instances.

The integration test related AWS resources are located in the repo https://github.com/Kong/terraform-self-hosted-runners, inside the module `gateway-integration-test`.
