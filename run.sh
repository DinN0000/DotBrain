#!/bin/bash
# Build, code-sign, and run AI-PKM-MenuBar
set -e
swift build
codesign --force --sign - .build/debug/AI-PKM-MenuBar
.build/debug/AI-PKM-MenuBar
