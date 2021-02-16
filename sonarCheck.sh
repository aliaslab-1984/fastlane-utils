#!/usr/bin/env bash

echo "Starting Sonar Scan"
cd $SCHEME
sonar-scanner
