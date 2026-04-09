#!/bin/bash

################################################################################
# Dev_Setup Installer Script for macOS
#
# This script installs the Dev_Setup application to /Applications and removes
# the macOS quarantine attribute to bypass Gatekeeper warnings.
#
# Usage:
#   ./install_app.sh
#
# The script will automatically find and install Dev_Setup.app
################################################################################

set -e

# Colors for better visual output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print header
clear
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║${NC}        ${BOLD}Dev_Setup Application Installer${NC}              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                 ${BOLD}for macOS${NC}                             ${CYAN}║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}This installer will:${NC}"
echo -e "  ${GREEN}•${NC} Copy Dev_Setup.app to /Applications"
echo -e "  ${GREEN}•${NC} Remove macOS security warnings (quarantine)"
echo -e "  ${GREEN}•${NC} Make the app ready to launch"
echo ""
echo -e "${YELLOW}Press Enter to continue or Ctrl+C to cancel...${NC}"
read -r
echo ""

# Function to find the app
find_app() {
    local app_path=""

    # Check if path was provided as argument
    if [ -n "$1" ] && [ -d "$1" ]; then
        app_path="$1"
        echo -e "${GREEN}✓${NC} Found app at: $app_path" >&2
        echo "$app_path"
        return 0
    fi

    # Check current directory
    if [ -d "./Dev_Setup.app" ]; then
        app_path="./Dev_Setup.app"
        echo -e "${GREEN}✓${NC} Found app in current directory" >&2
        echo "$app_path"
        return 0
    fi

    # Check for mounted DMG volume
    if [ -d "/Volumes/Dev_Setup/Dev_Setup.app" ]; then
        app_path="/Volumes/Dev_Setup/Dev_Setup.app"
        echo -e "${GREEN}✓${NC} Found app in mounted DMG volume" >&2
        echo "$app_path"
        return 0
    fi

    # Check Downloads folder
    if [ -d "$HOME/Downloads/Dev_Setup.app" ]; then
        app_path="$HOME/Downloads/Dev_Setup.app"
        echo -e "${GREEN}✓${NC} Found app in Downloads folder" >&2
        echo "$app_path"
        return 0
    fi

    echo -e "${RED}✗${NC} Could not find Dev_Setup.app" >&2
    echo "" >&2
    echo "Please provide the path to Dev_Setup.app:" >&2
    echo "  ./install_app.sh /path/to/Dev_Setup.app" >&2
    echo "" >&2
    echo "Or ensure the .dmg is mounted or the .app is in the current directory." >&2
    return 1
}

# Find the application
echo -e "${BLUE}[1/4]${NC} ${BOLD}Locating Dev_Setup.app...${NC}"
APP_SOURCE=$(find_app "$1")
if [ $? -ne 0 ]; then
    echo ""
    echo -e "${RED}═════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  Installation Failed${NC}"
    echo -e "${RED}═════════════════════════════════════════════════════${NC}"
    exit 1
fi
echo ""

# Check if already installed
if [ -d "/Applications/Dev_Setup.app" ]; then
    echo -e "${BLUE}[2/4]${NC} ${BOLD}Checking existing installation...${NC}"
    echo -e "${YELLOW}      ⚠  Dev_Setup.app is already installed${NC}"
    echo ""
    read -p "      Replace with new version? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}═════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  Installation Cancelled${NC}"
        echo -e "${YELLOW}═════════════════════════════════════════════════════${NC}"
        exit 0
    fi
    echo -e "      ${CYAN}→${NC} Removing old version..."
    rm -rf "/Applications/Dev_Setup.app"
    echo -e "      ${GREEN}✓ Removed${NC}"
    echo ""
fi

# Copy to Applications
echo -e "${BLUE}[3/4]${NC} ${BOLD}Installing to /Applications...${NC}"
echo -e "      ${CYAN}→${NC} Copying application files..."
cp -R "$APP_SOURCE" /Applications/
if [ $? -eq 0 ]; then
    echo -e "      ${GREEN}✓ Successfully installed${NC}"
else
    echo -e "      ${RED}✗ Failed to copy application${NC}"
    echo ""
    echo -e "${RED}═════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  Installation Failed${NC}"
    echo -e "${RED}═════════════════════════════════════════════════════${NC}"
    exit 1
fi
echo ""

# Remove quarantine attribute
echo -e "${BLUE}[4/4]${NC} ${BOLD}Configuring security settings...${NC}"
echo -e "      ${CYAN}→${NC} Removing macOS Gatekeeper restrictions..."
xattr -cr /Applications/Dev_Setup.app 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "      ${GREEN}✓ Security configuration complete${NC}"
    echo -e "      ${GREEN}✓ App will launch without warnings${NC}"
else
    echo -e "      ${YELLOW}⚠ Could not modify security settings${NC}"
    echo -e "      ${YELLOW}  If blocked, right-click → Open${NC}"
fi
echo ""

# Success message
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                            ║${NC}"
echo -e "${GREEN}║${NC}              ${BOLD}✓ Installation Complete!${NC}                  ${GREEN}║${NC}"
echo -e "${GREEN}║                                                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}How to launch Dev_Setup:${NC}"
echo ""
echo -e "  ${CYAN}Option 1:${NC} Finder → Applications → Dev_Setup"
echo -e "  ${CYAN}Option 2:${NC} Press ⌘+Space, type 'Dev_Setup', press Enter"
echo -e "  ${CYAN}Option 3:${NC} Run: ${YELLOW}open /Applications/Dev_Setup.app${NC}"
echo ""
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Ask to launch
read -p "Launch Dev_Setup now? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${CYAN}→${NC} Opening Dev_Setup..."
    sleep 1
    open /Applications/Dev_Setup.app
    echo -e "${GREEN}✓${NC} Dev_Setup is starting..."
    echo ""
    echo -e "${GREEN}Thank you for using Dev_Setup!${NC}"
else
    echo ""
    echo -e "${GREEN}Installation complete. Launch when ready!${NC}"
fi

echo ""
