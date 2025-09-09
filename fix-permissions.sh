#!/bin/bash
# Fix permission issues for transparent proxy system

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fixing Permissions for Transparent Proxy System${NC}"
echo "============================================"

# Function to check if running with proper permissions
check_docker_access() {
    if ! docker ps >/dev/null 2>&1; then
        echo -e "${RED}❌ Cannot access Docker. Trying to fix...${NC}"
        
        # Check if user is in docker group
        if ! groups | grep -q docker; then
            echo -e "${YELLOW}You're not in the docker group. Run:${NC}"
            echo "  sudo usermod -aG docker $USER"
            echo "  newgrp docker"
            echo ""
            echo "Or run this script with sudo:"
            echo "  sudo ./fix-permissions.sh"
            exit 1
        fi
    else
        echo -e "${GREEN}✅ Docker access OK${NC}"
    fi
}

# Function to fix file permissions
fix_file_permissions() {
    echo -e "\n${YELLOW}1. Fixing script permissions...${NC}"
    
    # Make all shell scripts executable
    find . -name "*.sh" -type f | while read script; do
        if [ ! -x "$script" ]; then
            chmod +x "$script" && echo "  Fixed: $script"
        fi
    done
    
    # Fix Python scripts
    find . -name "*.py" -type f | while read script; do
        if [ ! -x "$script" ]; then
            chmod +x "$script" && echo "  Fixed: $script"
        fi
    done
    
    echo -e "${GREEN}✅ Script permissions fixed${NC}"
}

# Function to fix Docker volumes
fix_docker_volumes() {
    echo -e "\n${YELLOW}2. Fixing Docker volume permissions...${NC}"
    
    # Create directories if they don't exist
    mkdir -p captured configs certs 2>/dev/null || true
    
    # Fix ownership (make them writable)
    chmod 755 captured configs certs 2>/dev/null || true
    
    # If running with sudo, also fix ownership
    if [ "$EUID" -eq 0 ]; then
        chown -R $(logname):$(logname) captured configs certs 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✅ Volume permissions fixed${NC}"
}

# Function to fix container permissions
fix_container_permissions() {
    echo -e "\n${YELLOW}3. Checking container permissions...${NC}"
    
    # Check if containers are running
    if docker ps | grep -q transparent-proxy; then
        echo "Fixing permissions in transparent-proxy container..."
        
        # Fix certificate directory
        docker exec transparent-proxy sh -c "
            mkdir -p /certs 2>/dev/null || true
            chmod 755 /certs 2>/dev/null || true
            mkdir -p /captured 2>/dev/null || true
            chmod 755 /captured 2>/dev/null || true
            
            # Try to create mitmproxy config directory with proper permissions
            mkdir -p ~/.mitmproxy 2>/dev/null || true
            mkdir -p /home/mitmproxy/.mitmproxy 2>/dev/null || true
            chmod 755 ~/.mitmproxy 2>/dev/null || true
            chmod 755 /home/mitmproxy/.mitmproxy 2>/dev/null || true
        " 2>/dev/null || echo "  Note: Some operations require container rebuild"
        
        echo -e "${GREEN}✅ Container permissions checked${NC}"
    else
        echo -e "${YELLOW}⚠️  Containers not running - will be fixed on next start${NC}"
    fi
}

# Function to test write permissions
test_permissions() {
    echo -e "\n${YELLOW}4. Testing write permissions...${NC}"
    
    # Test local directories
    for dir in captured configs certs; do
        if [ -d "$dir" ]; then
            if touch "$dir/.test" 2>/dev/null; then
                rm "$dir/.test"
                echo -e "  ${GREEN}✅ $dir is writable${NC}"
            else
                echo -e "  ${RED}❌ $dir is not writable${NC}"
            fi
        fi
    done
    
    # Test Docker
    if docker run --rm alpine echo "test" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Docker can create containers${NC}"
    else
        echo -e "  ${RED}❌ Docker cannot create containers${NC}"
    fi
}

# Function to clean and rebuild
clean_rebuild() {
    echo -e "\n${YELLOW}5. Clean rebuild recommended...${NC}"
    echo "Run these commands to ensure clean state:"
    echo ""
    echo "  # Stop and remove everything"
    echo "  docker compose -f docker-compose-transparent.yml down -v"
    echo ""
    echo "  # Remove old images"
    echo "  docker rmi proxy-3-app proxy-3-transparent-proxy proxy-3-viewer 2>/dev/null || true"
    echo ""
    echo "  # Rebuild from scratch"
    echo "  ./rebuild-proxy.sh --clean"
    echo ""
    echo "  # Start the system"
    echo "  ./start-proxy-system.sh"
}

# Main execution
echo -e "\n${BLUE}Starting permission fixes...${NC}"

# Check Docker access
check_docker_access

# Fix file permissions
fix_file_permissions

# Fix Docker volumes
fix_docker_volumes

# Fix container permissions
fix_container_permissions

# Test permissions
test_permissions

# Show rebuild instructions
clean_rebuild

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}Permission Fix Complete!${NC}"
echo -e "${BLUE}=========================================${NC}"

echo -e "\n${GREEN}Next steps:${NC}"
echo "1. If you still see permission errors, run with sudo:"
echo "   sudo ./fix-permissions.sh"
echo ""
echo "2. Then rebuild and start:"
echo "   ./rebuild-proxy.sh --clean"
echo "   ./start-proxy-system.sh"
echo ""
echo "3. If issues persist, check Docker daemon:"
echo "   sudo systemctl status docker"
echo "   sudo journalctl -u docker -n 50"