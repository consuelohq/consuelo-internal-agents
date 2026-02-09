#!/bin/bash
# Consuelo SDK installer
# Usage: curl -fsSL consuelohq.com/install | bash
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}▸${NC} $1"; }
warn()  { echo -e "${YELLOW}▸${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

echo -e "\n${BOLD}consuelo${NC} — AI-powered sales toolkit\n"

# Detect OS
OS="$(uname -s)"
ARCH="$(uname -m)"
info "detected: $OS $ARCH"

# Check for Node.js
if ! command -v node &>/dev/null; then
  error "node.js is required. install it from https://nodejs.org"
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
  error "node.js 18+ required (found v$NODE_VERSION)"
fi
info "node $(node -v) ✓"

# Detect package manager
if command -v bun &>/dev/null; then
  PM="bun"
  INSTALL="bun add -g"
elif command -v pnpm &>/dev/null; then
  PM="pnpm"
  INSTALL="pnpm add -g"
elif command -v yarn &>/dev/null; then
  PM="yarn"
  INSTALL="yarn global add"
else
  PM="npm"
  INSTALL="npm install -g"
fi
info "using $PM"

# Install
info "installing @consuelo/cli..."
$INSTALL @consuelo/cli 2>/dev/null || {
  warn "global install failed — trying npx instead"
  echo -e "\nyou can use consuelo via npx:"
  echo -e "  ${BOLD}npx consuelo init${NC}"
  echo -e "  ${BOLD}npx consuelo call +1234567890${NC}\n"
  exit 0
}

# Verify
if command -v consuelo &>/dev/null; then
  echo -e "\n${GREEN}✓${NC} consuelo installed successfully!\n"
  echo -e "get started:"
  echo -e "  ${BOLD}consuelo init${NC}        — set up credentials"
  echo -e "  ${BOLD}consuelo call <num>${NC}  — make a call"
  echo -e "  ${BOLD}consuelo status${NC}      — check config\n"
else
  warn "installed but 'consuelo' not in PATH"
  echo -e "try: ${BOLD}npx consuelo init${NC}\n"
fi
