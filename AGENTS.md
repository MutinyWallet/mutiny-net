# Deployment image tags

- Keep the SSP image at `ghcr.io/benthecarman/open-ssp:master` for easy
  deployment updates. Do not replace it with a `sha-*` tag or image digest
  unless the user requests it.
- Preserve the existing deployment image tag choices. Source revisions in
  Dockerfiles, such as `SPARK_REF`, are separate build pins.
- Keep both Spark operators on the `open-ssp-instant-deposits` image tag
  by default. Keep publishing that tag in the operator image workflow.
