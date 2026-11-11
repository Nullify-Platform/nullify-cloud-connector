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

The marketplace readiness PR prepares collector chart 0.6.1 because its README is part of the immutable chart package. It retains collector image 4.0.0 and the source-prefix contract. Published 0.6.0 remains unchanged. This patch is not yet published; publication requires Tim's approval.

Artifact Hub repository `nullify` (display name Nullify Kubernetes) was registered with Tim's explicit approval on 11 November 2026. Its assigned repository ID is `158135dc-d5cd-4016-9d22-5494d9510594`; processing is pending. The registration leaves security scanning enabled. The ownership metadata in `artifacthub-repo.yml` still needs to be served next to `index.yaml` before a Verified Publisher claim is established. No other marketplace submission or vendor message is authorized by this registration approval.

The prepared release now includes a public consumer check for index versions, package digests, chart identities and Artifact Hub ownership metadata. A full local repository dry run retained all four published chart versions and prepared collector 0.6.1 without replacing immutable 0.6.0. Routing RBAC, upload-scope tests, chart lint/render cases and the readonly raw-manifest comparison passed. These checks do not establish a live customer installation or publish the prepared version.
