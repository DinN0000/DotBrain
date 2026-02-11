#!/bin/bash
# Build, code-sign, and run DotBrain
set -e
swift build
codesign --force --sign - .build/debug/DotBrain
.build/debug/DotBrain
