# Cloud package publication status

On 11 November 2026, the current-main Helm publication workflow completed and both charts became publicly downloadable:

| Chart | Version | Package SHA256 |
| --- | --- | --- |
| nullify-k8s-collector | 0.6.0 | 9c226f4fdf56f9d717413407fa7271b307096c51c3e658f3a65ff7a7554c8d44 |
| nullify-k8s-readonly-access | 0.1.0 | 6affcdb7b182211001b6c8feaff4089e41bf6172abe6f2afca04d28ed4ca1f3a |

[Publication run](https://github.com/Nullify-Platform/nullify-cloud-connector/actions/runs/42922224437) used main commit `54681d5f5b6fb9ffd19380081edda5bcd23f995e`. Both downloaded packages matched the [public index](https://nullify-platform.github.io/nullify-cloud-connector/index.yaml) digests and rendered successfully. Existing 0.5.0 remains in the index with its original digest.

The stale 4 and 5 November runs were waiting/pending behind the protected GitHub Pages environment. They were cancelled before dispatching and approving publication from current main; environment protections were preserved.

Collector 4 publication does not activate a compatible backend or provision upload trust. Existing tenants need the exact source-qualified upload prefix and coordinated IAM/backend rollout before upgrading. The readonly-access chart only grants Kubernetes API access; it does not install a workload or establish an EKS access entry.

Artifact Hub registration remains separate from publishing a Helm repository. Terraform Registry and commercial Azure/GCP marketplace offers also require their own repository, publisher and fulfillment requirements; they are not created by this workflow.
