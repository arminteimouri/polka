#!/bin/bash

POLKADOT_VERSION="v0.9.12"
# Archive RPC nodes
helm upgrade --install polka-node . \
  --namespace polkadot
