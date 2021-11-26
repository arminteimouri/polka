# Simple Polkadot Node Deployer
 
This helm chart will deploy a Polkadot node (not in validator mode). 
To deploy the node, you need to clone this project, change the directory to it, and execute the run.sh script  
```sh
git clone https://github.com/arminteimouri/polka.git
cd polka
sh run.sh
```
## How to check it after deployment:
First, check the PODs in the statefullset
```sh
kubetctl get po -n polkadot
```
Then run a network utils pod within the same namespace or another namespace and curl the Headless service on `http-rpc port` and health endpoint and examine the isSyncing status and number of peers.
```sh
kubectl run -i --tty --rm  networkutils --image=praqma/network-multitool --restart=Never -n polkadot -- sh
curl polka-node-polkadot:9933/health
```

## How it works:
Right after the container initiation, it will try to download the genesis block and the rest of the chain. If you have already enabled external exposing of Prometheus/RPC/... ports, they will be accessible to the pods and services.

Readiness and Liveness probs should be considered as well but I need to know more about the application logic to understand which method of examining the process state fits better with it.

# Bonus part plus my further investigations (Mainly in Security):
We tried to examine the Polkadot binary while configured to run as in none validator mode and tried to `trace the kernel syscall` of the binary.
I did it using `strace utility` against the Polkadot's PID.
```sh
mkdir /strace
strace -o /strace/strace.log -f -s4096 -r ./polkadot --name=arminTeimouriNode2 --base-path=/tmp/ --chain=westend --port=30333 --prometheus-external --rpc-external --ws-external --rpc-cors=all"
```
I gave it enough time to sync the chain, and later I tried to examine the strace.log to find out all of the syscalls made to the Kernel.
```sh
cat /strace/strace.log | cut -d"(" -f1 | awk '{print $3}' | sort -h | uniq
accept4
access
arch_prctl
bind
brk
clock_gettime
clone
close
connect
epoll_create1
epoll_ctl
epoll_wait
...
...
```
Now I know what set of Syscalls the Polkadot binary is issuing to the Kernel, and  I'm able to create my SecComp profile `polka-seccomp.json` based on that. [polka-seccomp.json]
```sh
cat polka-seccomp.json
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "architectures": [
        "SCMP_ARCH_X86_64",
        "SCMP_ARCH_X86",
        "SCMP_ARCH_X32"
    ],
    "syscalls": [
        {
            "names": [
                "accept4",
                "access",
...
...
                "unlink",
                "write"
            ],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
```
If your kubelet is configured in a way that supports the `SeccompDefault feature gate, then you will be able to place the profile in the seccomp profile directory of your worker nodes and then load it in your pod within the securityContext.

```
apiVersion: v1
kind: Pod
...
...
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/polka-seccomp.json
```
<https://kubernetes.io/blog/2021/08/25/seccomp-default/#feature-gate-enabling>

#### What does it bring for you? 
To `limit the attack vector` of a subverted process running in a container, the seccomp Linux kernel feature can be used to limit which syscalls a process has access to. We can think of that as a `firewall for syscalls.`

##### But what will happen if the developers change the code and the application's logic requires extra syscalls to fulfill its runtime requirements?
In the case of changes in the application's logic, we as the cluster administrator, need to be informed about such major changes and add those newly required syscalls to our seccomp profile.

##### Why didn't I choose the `Capability sets` restriction method?
Capability sets are not fine-grained enough, and each capability covers a set of syscalls. On the other hand, there is no magic tool out there that tells you the exact required capabilities of a binary. That is something that is expected to be provided by the developer.

Although there are ways to shed light on this matter by checking `'grep Cap /proc/PID/status'` and checking the permitted and effective sets or even using "[capable tracer utility]" which comes with the BPF compiler collection.

## Regarding lifecycle hooks within the Container's spec:
I checked the Polkadot binary and traced its behavior while it received SIGINT (If the Kubernetes decides to take down the POD by any means, it will first execute the preStop hooks and later on will send a SIGINT signal to the process).
We need to ensure that the process `traps the SIGINT properly` and `does a clean shutdown` of itself.
```sh
kill -SIGINT pidOfPolakdotBinary
```
examining the strace log:
```sh
24138      0.000114 openat(AT_FDCWD, "/tmp/chains/westend2/db/full/parachains/db", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY <unfinished ...>
...
24138      0.000010 write(50, "2021/11/26-08:16:42.185714 7f8c88b96000 [db/db_impl/db_impl.cc:463] Shutdown: canceling all background work\n", 108 <unfinished ...>
24138      0.000031 close(16 <unfinished ...>
..
24298      0.000004 mmap(NULL, 4190208, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0 <unfinished ...>
24138      0.000011 write(50, "2021/11/26-08:16:42.189000 7f8c88b96000 [db/db_impl/db_impl.cc:642] Shutdown complete\n", 86 <unfinished ...>
..
24143      0.000004 write(9, "2021/11/26-08:16:42.192829 7f8c85bff700 (Original Log Time 2021/11/26-08:16:42.183281) [db/db_impl/db_impl_compaction_flush.cc:3046] [col5] Moving #26116 to level-5 297795 bytes\n2021/11/26-08:16:42.192832 7f8c85bff700 (Original Log Time 2021/11/26-08:16:42.192779) EVENT_LOG_v1 {\"time_micros\": 1637914602192774, \"job\": 11, \"event\": \"trivial_move\", \"destination_level\": 5, \"files\": 1, \"total_files_size\": 297795}\n2021/11/26-08:16:42.192834 7f8c85bff700 (Original Log Time 2021/11/26-08:16:42.192789) [db/db_impl/db_impl_compaction_flush.cc:3076] [col5] Moved #1 files to level-5 297795 bytes OK: base level 4 level multiplier 10.00 max bytes base 1048576 files[1 0 0 0 5 5 49] max score 1.03\n", 691 <unfinished ...>
..
24297      0.000007 +++ exited with 0 +++
24296      0.000002 +++ exited with 0 +++
```
I discovered that it will cancel all background work and does a clean shutdown. So no preStop hook is required as the developer has already handled SIGINT properly(based on my current investigation).

## Applying network policies:
I need to know more about the polkadot but with my current limited knowledge about that, I thought that 4 ports need to receive incoming traffic so I added the `networkPolicy.yaml` manifest.
But it needs to be supported by your CNI so I did a validation on the manifest to know whether the related API group is available on your cluster or not.
`{{- if .Capabilities.APIVersions.Has "networking.k8s.io/v1/NetworkPolicy" }}`
<https://github.com/arminteimouri/polka/blob/main/templates/networkPolicy.yaml>
 
 
## Configuring SecurityContext:
While examining the DockerFile of the latest polkadot release, you will see how the user is created and which user will execute the binary.
<https://github.com/paritytech/polkadot/blob/ec34cf7e059b91609e5b3ac4ae0f604b34ce01d9/scripts/dockerfiles/polkadot_injected_release.Dockerfile#L28>
```sh
# install tools and dependencies
RUN apt-get update && \
..
	useradd -m -u 1000 -U -s /bin/sh -d /polkadot polkadot && \
..
USER polkadot
```
So I decided to add the following config within the sts.spec.template.spec.securityContext
```sh
apiVersion: apps/v1
kind: StatefulSet
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
```
and also this config within the sts.spec.template.spec.containers[].securityContext
```sh
apiVersion: apps/v1
kind: StatefulSet
spec:
  template:
    spec:
      containers:
      - name: polkadot
        securityContext:
          allowPrivilegeEscalation: false
          runAsGroup: 1000
          runAsUser: 1000
```




  [capable tracer utility]: <https://github.com/iovisor/bcc>
  [polka-seccomp.json]: <https://github.com/arminteimouri/polka/blob/main/polka-seccomp.json>