# Simple Polkadot Node  Deployment
 
With Polkadot binary you can easily connect to  global Polkadot networks and define your role (Full/Validator/...) and use the Built-in prometheus metrics or event send the telemetry to the telemetry defined URL (as arguments to the binary) with the desired verbosity.

All you need to do is to apply this deployment on your k8s cluster.    
```sh
kubectl apply -f deployment.yaml -n YourDesiredNameSpace
```
## How it works:
Just right after the container initiation, it will try to download the genesis block and the rest of the chain. Depend on if you have already enabled external exposing of prometheus/rpc/... ports, they will be accessible to the pods and services.

# /data dir
Chain will be downloaded in this dir so we should take care of this directory as downloading/syncing the chain is both time and resource intensive task. Using PVC and Snappshots of previously synced Volumes on the cluster may help accelerating this procedure and can be considered.

Readyness and Liveness probs should be considered as well but I need to know more about the application to understand which method should be implemented for each of them.