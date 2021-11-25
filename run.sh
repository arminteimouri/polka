#!/bin/bash
# --reuse-values: 
# There is always the possibility of facing a risk that one team member applies the helm and sets one of the values on the air
# using  --set while applying the helm chart. In that case, specific custom values are configured on the latest release that
# you are unaware of them. Using this flag will keep reusing those values on your current run and guarantee the integrity
# between deployments.
helm upgrade --install  --reuse-values polka-node . --namespace polkadot
