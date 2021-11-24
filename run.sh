#!/bin/bash
# --reuse-values: There is always the possibility of facing with a risk that one of the team members, apply the helm and manipulate one of the values
# using  --set. On that case there are specific custom values configure on the current release that you are not aware of.
# using this flag will keep reuse those values on your current apply and guaranty the integrity between deployments.
helm upgrade --install  --reuse-values polka-node . --namespace polkadot
