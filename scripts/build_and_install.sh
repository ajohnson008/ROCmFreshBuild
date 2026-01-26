#!/usr/bin/env bash
set -e

# Define build directory
BUILD_DIR="build_results"

echo "🚀 Starting Standardized Build..."

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

# Clean up old root-level result symlinks to avoid confusion
echo "🧹 Cleaning up old result symlinks..."
rm -f result result-*

# Build the AI stack and output to the unified folder
echo "🔨 Building .#ai-stack into $BUILD_DIR/result..."
nix build .#ai-stack --out-link "$BUILD_DIR/result" --print-build-logs

echo "✅ Build Complete!"
echo "📂 Output is located at: $BUILD_DIR/result"
