# Runbooks

Short, first-response runbooks for the alerts in [`alerts/`](../alerts). Each
alert's `runbook_url` points at a section here. The format is always the same:
**what it means → first checks → usual fixes**. Write down anything you learn
during an incident here, so the next responder starts from it.

Upstream kube-prometheus-stack alerts link to
[runbooks.prometheus-operator.dev](https://runbooks.prometheus-operator.dev/).

---

## SLOErrorBudgetBurn

`SLOErrorBudgetBurnFast` (critical, pages) / `SLOErrorBudgetBurnSlow` (warning).

**Meaning.** The service fails its SLI (5xx responses, or requests slower than
the latency threshold) fast enough to use up the 30-day error budget early.
Fast means the budget is gone in less than 5 days at the current rate, so users
are affected right now.

**First checks**
1. Open the **SLO / Error Budget** dashboard (`dashboard_url` annotation). Check
   which window is burning and whether it is getting better or worse.
2. Was there a deploy or config change around the start? `kubectl rollout history`, Argo CD history.
3. Check dependencies: database, downstream APIs, DNS, and node or zone issues.
4. Open the **Logs / Volume & Errors** dashboard filtered to the service's namespace.

**Usual fixes.** Roll back the last change. Scale out if the cause is
saturation. Fail over or shed load if a dependency is down. Once the impact
stops, the fast alert resolves within about an hour (the long window has to
recover). That delay is expected.

## KubeNodeNotReady

**Meaning.** The kubelet has stopped reporting Ready for 15 minutes.

**First checks.** Run `kubectl describe node <node>` and read the conditions and
events. Check the instance in the cloud console (status checks, spot
interruption). Check whether Karpenter or Cluster Autoscaler is already
replacing the node.

**Usual fixes.** If the autoscaler does not replace the node, run `kubectl drain`
on it and terminate the instance. If several nodes fail together, suspect the
network, the CNI, or the control plane rather than the nodes.

## KubeNodePressure

`KubeNodeMemoryPressure`, `KubeNodeDiskPressure`, `KubeNodePIDPressure`.

**Meaning.** The kubelet is under resource pressure and will evict pods.

**First checks**
- Memory: find pods whose working set is far above their requests, or pods
  without memory limits (cost dashboard, "Memory used by namespace").
- Disk: `kubectl debug node/<node> -it --image=busybox -- df -h /host`. Usual
  causes are large container logs, images, or emptyDir volumes.
- PID: find the process leaking threads or processes.

**Usual fixes.** Set realistic requests and limits. Add ephemeral-storage
limits. Increase the node root volume in the NodeClass or launch template.

## KubeNodeMemoryRequestsOvercommitted

**Meaning.** The memory requests of running pods add up to more than the node's
allocatable memory. The scheduler never places pods this way, so allocatable
changed after the pods were scheduled. A kubelet `--kube-reserved` change or a
smaller instance type behind the same name can cause this.

**Fix.** Drain the node so its pods are scheduled again under the current
allocatable.

## KubePodCrashLooping

**First checks**
```sh
kubectl -n <ns> logs <pod> -c <container> --previous
kubectl -n <ns> describe pod <pod>    # exit code, OOMKilled, probe failures
```
**Usual causes.** A bad config or secret, a dependency that cannot be reached
at startup, a liveness probe that is too strict, or OOM (see below).

## KubeContainerOOMKilled

**Meaning.** The container went over its memory limit and the kernel killed it.

**Fix.** Compare the limit with the p99 working set over 7 days. Raise the limit
or fix the leak. For JVM, Node and similar runtimes, check that the heap size
follows the container limit.

## KubeReplicasMismatch

`KubeDeploymentReplicasMismatch`, `KubeStatefulSetReplicasMismatch`.

**Meaning.** Fewer replicas are available than desired for 15 minutes, and the
rollout has made no progress in that time.

**First checks.** `kubectl -n <ns> get pods -l <selector>` shows whether the
missing pods are Pending, CrashLooping or failing readiness. Pending pods lead
to *KubePodUnschedulable*.

## KubeJobFailed

**Fix.** Read the logs of the failed pod. Once handled, delete the Job (or set
`ttlSecondsAfterFinished`) so the alert clears.

## KubeHpaMaxedOut

**Meaning.** The HPA has been at `maxReplicas` for 30 minutes, so the service
cannot scale further.

**Fix.** Check whether the load is real (traffic dashboards) or a regression
raised the cost per request. Raise `maxReplicas` if the cluster has room.

## KubePersistentVolumeFillingUp

`KubePersistentVolumeFillingUp` (critical, under 3% free),
`KubePersistentVolumeFillingUpPredicted` (warning, full within 4 days),
`KubePersistentVolumeInodesFillingUp`.

**Fix.** If the StorageClass has `allowVolumeExpansion: true`, edit the PVC's
`spec.resources.requests.storage` (EBS gp3 resizes online). Otherwise free up
space: clean old WAL, logs or snapshots, or tighten the application's retention.

## KubePersistentVolumeErrors

**First checks.** Run `kubectl describe pv <pv>` and read the CSI driver
controller logs (`ebs-csi-controller`). Usual causes are IAM permissions, the
AZ of the volume and the AZ of the pod not matching, and volume quotas.

## KubePodUnschedulable

**Meaning.** A pod has been unschedulable for 15 minutes, and no node autoscaler
added capacity for it.

**First checks.** `kubectl -n <ns> describe pod <pod>` shows the scheduler
events. With Karpenter, also check `kubectl get nodeclaims` and the Karpenter
logs. With Cluster Autoscaler, check its status ConfigMap and events.

**Usual causes.** A NodePool or node-group limit was reached (see below). No
instance type matches the requirements (GPU, arch, zone). The
`nodeSelector`, affinity or topology spread is too strict. A PVC is pinned to a
different AZ.

## KarpenterCloudProviderErrors

**Meaning.** Calls from Karpenter to the cloud API keep failing. The `error`
label is usually enough to tell why: `InsufficientCapacityError`, an
`UnauthorizedOperation` caused by IAM drift, or a service quota.

**Fix.** For capacity errors, widen the instance families or zones in the
NodePool, or allow on-demand as a fallback to spot. For IAM errors, compare the
controller role with the policy of the Karpenter version you run.

## KarpenterNodePoolLimitNearlyReached

**Fix.** Raise `spec.limits` on the NodePool if the growth is expected.
Otherwise find the workload that grew, using the cost dashboard sorted by
namespace.

## ClusterAutoscalerUnschedulablePods

**First checks.** `kubectl -n kube-system get cm cluster-autoscaler-status -o yaml`
shows the per-node-group scale-up status and backoff.

## ClusterAutoscalerNotSafeToScale

**Meaning.** Too many nodes are unready, so Cluster Autoscaler stops scaling
until the cluster recovers. Fix the unready nodes first (*KubeNodeNotReady*).

## ClusterAutoscalerMaxNodesReached

**Fix.** Raise `--max-nodes-total`, or the max size of the node group, if the
growth is expected.

## CertificateExpiry

`CertManagerCertificateExpiringSoon`, `CertManagerCertificateExpiryCritical`,
`CertManagerCertificateNotReady`, `TLSEndpointCertificateExpiringSoon`.

**First checks**
```sh
kubectl -n <ns> describe certificate <name>
kubectl -n <ns> get certificaterequests,orders,challenges
kubectl -n cert-manager logs deploy/cert-manager --since=1h
```
**Usual causes.** The ACME HTTP-01 challenge cannot be reached (ingress or WAF
change). DNS-01 credentials or IAM changed. The ACME account hit a rate limit.
For certificates that cert-manager does not manage (`TLSEndpoint…`), renew them
where they are issued, for example ACM or a vendor portal.
