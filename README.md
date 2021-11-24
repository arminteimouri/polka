# Simple Polkadot Node  Deployment
 
 This will deploy a polkadot not (not in validator mode). 
We  tried to examine the Polkadot binary while it was configured to run as in none validator mode and tried to trace the kernel syscall of the binary.
Based on the gathered data we create the polka-seccomp.json file.
If you have configured your kubelet to support SeccompDefault feature-gate, then you will be able to place that in the seccomp profile directories of your worker nodes and then load it in your pod within the securityContext.
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
polkadot binary while being executed in none validator mode and captured the syscalls of the application and made a seccomp profile based on that. So on case of application compomisation, it will be hard for the attacker to do things more than the limited number of syscall available for the process.


In order to deploy the node, All you need to do is to clone this project and change directory to it and execute the run.sh script  
* --wait 
```sh
sh run.sh
```
## How to check it after deployment:
First check the PODs in the statefullset
```
kubetctl get po -n polkadot
```
Then run a network utils pod within the same namespace or another namespace and curl the Headless service on http-rpc port and health endpoint and see the isSyncing status and number of peers
```
kubectl run -i --tty --rm  networkutils --image=praqma/network-multitool --restart=Never -n polkadot -- sh
curl polka-node-polkadot:9933/health
```



## How it works:
Just right after the container initiation, it will try to download the genesis block and the rest of the chain. Depend on if you have already enabled external exposing of prometheus/rpc/... ports, they will be accessible to the pods and services.

# /data dir
Chain will be downloaded in this dir so we should take care of this directory as downloading/syncing the chain is both time and resource intensive task. Using PVC and Snappshots of previously synced Volumes on the cluster may help accelerating this procedure and can be considered.

Readyness and Liveness probs should be considered as well but I need to know more about the application to understand which method should be implemented for each of them.
