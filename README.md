# Simple Polkadot Node Deployer
 
This helm chart will deploy a Polkadot node (not in validator mode). 
To deploy the node, you need to clone this project, change the directory to it, and execute the run.sh script  
```sh
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
Right after the container initiation, it will try to download the genesis block and the rest of the chain. If you have already enabled external exposing of prometheus/rpc/... ports, they will be accessible to the pods and services.


Readiness and Liveness probs should be considered as well but I need to know more about the application logic to understand which method of examining the process state fits better with it.

## Bonus part plus my further investigations:
We tried to examine the Polkadot binary while configured to run as in none validator mode and tried to `trace the kernel syscall` of the binary.
I did it using `strace utility` against the Polkadot's PID.
```sh
mkdir /strace
strace -o /strace/strace.log -f -s4096 -r ./polkadot --name=arminTeimouriNode2 --base-path=/tmp/ --chain=westend --port=30333 --prometheus-external --rpc-external --ws-external --rpc-cors=all --telemetry-url "https://telemetry.polkadot.io 1"
```
I gave it enough time to sync the chain, and later I tried to examine the strace.log to find out all of the syscalls made to the Kernel.
```sh
cat /strace/strace.log | cut -d"(" -f1 | awk '{print $3}' | sort -h | uniq
```
Now I know what set of Syscalls the Polkadot binary is issuing to the Kernel, and  I'm able to create my SecComp profile polka-seccomp.json based on that.
If your kubelet is configured in a way that supports `SeccompDefault feature-gate`, then you will be able to place the profile in the seccomp profile directory of your worker nodes and then load it in your pod within the securityContext.
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
#### What does it bring for you? 
To `limit the attack vector` of a subverted process running in a container, the seccomp Linux kernel feature can be used to limit which syscalls a process has access to. We can think of that as a `firewall for syscalls.`
In the case of application compromisation, it will be impossible for the attacker to do things more than the limited number of syscalls available for the process. We know the required syscalls by our application, and we have limited the container process to those sets of syscalls.

##### But what will happen if the developers change the code and the application's logic requires extra syscalls to full-fill its runtime requirements?
In the case of changes in the application's logic, we as the cluster administrator, need to be informed about such major change and add those newly required syscalls to our seccomp profile.

##### Why I didn't approached with `Capability sets` restriction?
Capability sets are not fine-grained enough and each capability covers a set of syscalls and on the other hand there is not a magic tool out there which tells you the exact required capabilities of a binary. That is something which is expected to be provided by the developer.

Although there are ways to shed light on this matter by checking `'grep Cap /proc/PID/status'` and checking the permited and effective sets or even using "[capable tracer utility]" which comes with the BPF compiler collection.
So if you have such a fine-grained approach in the security,  it will be much better to approach Seccomp instead of capability sets.

## Regarding lifecycle hooks within the Container's spec:
I checked the Polkadot binary and traced its behavior while it received SIGINT (If the Kubernetes decides to take down the POD by any means, it will first execute the preStop hooks and later on will send a SIGINT signal to the process).
We need to ensure that the process traps the SIGINT properly and does a clean shutdown of itself.
I ran the binary on the server and `traced it using strace` and in the other session, I issued a `SIGINT to the PID` of the Polkadot process. I discovered that it will cancel all background work and does a clean shutdown. So no preStop hook is required as the developer has already handled SIGINT properly(based on my current investigation).


  [capable tracer utility]: <https://github.com/iovisor/bcc>