#!/bin/bash

# Build
./build.sh

# Run
pushd basice2e
./run.sh
popd

# View result logs
# Not using $EDITOR or $VISUAL because many editors that people set those to
# don't have as easy support for viewing multiple files
${INTEGRATION_EDITOR:-gedit} ./basice2e/results/clients/*.out ./basice2e/results/servers/*.console ./basice2e/results/gateway.log ./basice2e/results/channelbot.console&
