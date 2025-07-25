#!/bin/bash

# DealMate Master Run Script
# This is the ONE SCRIPT to run everything - build, start, test, and monitor
# Usage: ./run_prod.sh

set -e

# Load environment variables
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 DealMate Master Application Runner (Production Mode)${NC}"
echo "====================================="
echo -e "${CYAN}This script will:${NC}"
echo "1. 🔧 Build all components for production"
echo "2. 🚀 Start all services"
echo "3. 🧪 Run health checks"
echo "4. 📊 Show platform status"
echo "5. 🎯 Keep services running"
echo ""

# Function to show spinner while waiting
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to check if services are running
check_services_running() {
    local ai_running=false
    local auth_running=false
    local backend_running=false
    local frontend_running=false
    
    if curl -s --max-time 2 "http://localhost:8001" > /dev/null 2>&1; then
        ai_running=true
    fi
    
    if curl -s --max-time 2 "http://localhost:3001/api/public" > /dev/null 2>&1; then
        auth_running=true
    fi
    
    if curl -s --max-time 2 "http://localhost:8000" > /dev/null 2>&1; then
        backend_running=true
    fi
    
    if curl -s --max-time 2 "http://localhost:9002" > /dev/null 2>&1; then
        frontend_running=true
    fi
    
    if [ "$ai_running" = true ] && [ "$auth_running" = true ] && [ "$backend_running" = true ] && [ "$frontend_running" = true ]; then
        return 0
    else
        return 1
    fi
}

# Check if services are already running
if check_services_running; then
    echo -e "${YELLOW}⚠️  Services appear to be already running!${NC}"
    echo -e "${YELLOW}Do you want to restart them? (y/N): ${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eS]|[yY])$ ]]; then
        echo -e "${YELLOW}🛑 Stopping existing services...${NC}"
        # Kill existing services
        pkill -f "dealmate-backend" 2>/dev/null || true
        pkill -f "python main.py" 2>/dev/null || true
        pkill -f "node.*auth-service" 2>/dev/null || true
        pkill -f "npm.*start\|next.*start" 2>/dev/null || true
        sleep 2
    else
        echo -e "${GREEN}✅ Skipping to health checks...${NC}"
        echo ""
        ./scripts/status.sh
        exit 0
    fi
fi

# Step 1: Build everything
echo -e "${BLUE}📦 Step 1: Building All Components for Production${NC}"
echo "=================================="
./scripts/build_prod.sh
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Production build completed successfully${NC}"
else
    echo -e "${RED}❌ Production build failed! Exiting...${NC}"
    exit 1
fi
echo ""

# Step 2: Start all services
echo -e "${BLUE}🚀 Step 2: Starting All Services${NC}"
echo "================================="

# Start AI Service
echo -e "${YELLOW}🤖 Starting AI Service...${NC}"
cd backend/ai-service
nohup python main.py > ../../logs/ai-service.log 2>&1 &
AI_SERVICE_PID=$!
cd ../../
echo "AI Service PID: $AI_SERVICE_PID"

# Wait for AI service to start
echo -e "${YELLOW}⏳ Waiting for AI service to initialize...${NC}"
sleep 5

# Start Auth Service
echo -e "${YELLOW}🔐 Starting Auth Service...${NC}"
nohup node backend/auth-service/index.js > logs/auth-service.log 2>&1 &
AUTH_SERVICE_PID=$!
echo "Auth Service PID: $AUTH_SERVICE_PID"

# Wait for auth service to start
echo -e "${YELLOW}⏳ Waiting for auth service to initialize...${NC}"
sleep 3

# Start Backend
echo -e "${YELLOW}🦀 Starting Backend...${NC}"
cd backend
nohup ./target/release/dealmate-backend > ../backend.log 2>&1 &
BACKEND_PID=$!
cd ..
echo "Backend PID: $BACKEND_PID"

# Wait for backend to start
echo -e "${YELLOW}⏳ Waiting for backend to initialize...${NC}"
sleep 3

# Start Frontend
echo -e "${YELLOW}📦 Starting Frontend...${NC}"
cd frontend
nohup npm run start > ../logs/frontend.log 2>&1 &
FRONTEND_PID=$!
cd ..
echo "Frontend PID: $FRONTEND_PID"

# Wait for frontend to start
echo -e "${YELLOW}⏳ Waiting for frontend to initialize...${NC}"
sleep 8

echo -e "${GREEN}✅ All services started${NC}"
echo ""

# Step 3: Health checks
echo -e "${BLUE}🧪 Step 3: Running Health Checks${NC}"
echo "================================="

# Wait a bit more for services to fully start
echo -e "${YELLOW}⏳ Allowing services to fully initialize...${NC}"
sleep 5

# Check each service
echo -e "${YELLOW}Testing AI Service...${NC}"
if curl -s --max-time 10 "http://localhost:8001" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ AI Service is responding${NC}"
else
    echo -e "${RED}❌ AI Service not responding${NC}"
fi

echo -e "${YELLOW}Testing Auth Service...${NC}"
if curl -s --max-time 10 "http://localhost:3001/api/public" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Auth Service is responding${NC}"
else
    echo -e "${RED}❌ Auth Service not responding${NC}"
fi

echo -e "${YELLOW}Testing Backend...${NC}"
if curl -s --max-time 10 "http://localhost:8000/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Backend is responding${NC}"
else
    echo -e "${RED}❌ Backend not responding${NC}"
fi

echo -e "${YELLOW}Testing Frontend...${NC}"
if curl -s --max-time 10 "http://localhost:9002" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Frontend is responding${NC}"
else
    echo -e "${RED}❌ Frontend not responding${NC}"
fi

echo ""

# Step 4: Platform status
echo -e "${BLUE}📊 Step 4: Platform Status${NC}"
echo "=========================="
./scripts/status.sh
echo ""

# Step 5: Keep running and show info
echo -e "${BLUE}🎯 Step 5: DealMate Platform Running${NC}"
echo "==================================="
echo -e "${GREEN}🎉 DealMate platform is now fully operational!${NC}"
echo ""
echo -e "${CYAN}📱 Application URLs:${NC}"
echo -e "  🤖 AI Service:     ${YELLOW}http://localhost:8001${NC}"
echo -e "  🔐 Auth Service:   ${YELLOW}http://localhost:3001${NC}"
echo -e "  🦀 Backend API:    ${YELLOW}http://localhost:8000${NC}"
echo -e "  📦 Frontend App:   ${YELLOW}http://localhost:9002${NC}"
echo -e "  📚 API Docs:       ${YELLOW}http://localhost:8001/docs${NC}"
echo ""
echo -e "${CYAN}📋 Service Information:${NC}"
echo -e "  AI Service PID:    $AI_SERVICE_PID"
echo -e "  Auth Service PID:  $AUTH_SERVICE_PID"
echo -e "  Backend PID:       $BACKEND_PID"
echo -e "  Frontend PID:      $FRONTEND_PID"
echo ""
echo -e "${CYAN}📄 Logs:${NC}"
echo -e "  AI Service:        tail -f logs/ai-service.log"
echo -e "  Auth Service:      tail -f logs/auth-service.log"
echo -e "  Backend:           tail -f logs/backend.log"
echo -e "  Frontend:          tail -f logs/frontend.log"
echo ""
echo -e "${CYAN}🔧 Management Commands:${NC}"
echo -e "  Status Check:      ./scripts/status.sh"
echo -e "  Run Tests:         ./scripts/test_all.sh"
echo -e "  Stop Services:     Press Ctrl+C or run: kill $AI_SERVICE_PID $AUTH_SERVICE_PID $BACKEND_PID $FRONTEND_PID"
echo ""
echo -e "${GREEN}🎯 Ready for browser extension testing!${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Shutting down DealMate platform...${NC}"
    kill $AI_SERVICE_PID $AUTH_SERVICE_PID $BACKEND_PID $FRONTEND_PID 2>/dev/null || true
    echo -e "${GREEN}✅ All services stopped${NC}"
    echo -e "${BLUE}👋 Thank you for using DealMate!${NC}"
    exit 0
}

# Set up signal handling
trap cleanup INT TERM

# Keep script running and show periodic status
while true; do
    sleep 30
    echo -e "${CYAN}[$(date '+%H:%M:%S')] Services running... (Press Ctrl+C to stop)${NC}"
done
