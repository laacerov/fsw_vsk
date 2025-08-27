#!/bin/bash

# =============================================================================
# FreeSWITCH Voicemail Detection System - Deployment Script
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="FreeSWITCH Voicemail Detection System"
REPO_URL="https://github.com/YOUR_USERNAME/freeswitch-voicemail-detection.git"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} $PROJECT_NAME${NC}"
echo -e "${BLUE} Deployment Script${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}⚠️  Este script no debe ejecutarse como root${NC}" 
   exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check dependencies
echo -e "${YELLOW}🔍 Verificando dependencias...${NC}"

if ! command_exists docker; then
    echo -e "${RED}❌ Docker no está instalado${NC}"
    echo -e "${YELLOW}Instalando Docker...${NC}"
    
    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    echo -e "${GREEN}✅ Docker instalado. Por favor reinicia la sesión y ejecuta el script nuevamente.${NC}"
    exit 0
fi

if ! command_exists docker-compose; then
    echo -e "${RED}❌ Docker Compose no está instalado${NC}"
    echo -e "${YELLOW}Instalando Docker Compose...${NC}"
    
    # Install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

if ! command_exists git; then
    echo -e "${RED}❌ Git no está instalado${NC}"
    echo -e "${YELLOW}Instalando Git...${NC}"
    
    # Install Git
    sudo apt update
    sudo apt install -y git
fi

echo -e "${GREEN}✅ Todas las dependencias están instaladas${NC}"

# Create project directory
PROJECT_DIR="$HOME/freeswitch-voicemail-detection"
echo -e "${YELLOW}📁 Creando directorio del proyecto: $PROJECT_DIR${NC}"

if [ -d "$PROJECT_DIR" ]; then
    echo -e "${YELLOW}⚠️  El directorio ya existe. Actualizando...${NC}"
    cd "$PROJECT_DIR"
    git pull origin main
else
    echo -e "${YELLOW}📥 Clonando repositorio...${NC}"
    git clone "$REPO_URL" "$PROJECT_DIR"
    cd "$PROJECT_DIR"
fi

# Copy environment file if it doesn't exist
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚙️  Creando archivo de configuración (.env)...${NC}"
    cp .env.example .env
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}⚠️  IMPORTANTE: Configura el archivo .env${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "${YELLOW}IP detectada del servidor: $SERVER_IP${NC}"
    
    # Update .env with server IP
    sed -i "s/FREESWITCH_EXTERNAL_IP=192.168.100.50/FREESWITCH_EXTERNAL_IP=$SERVER_IP/g" .env
    
    echo -e "${GREEN}✅ Archivo .env configurado con IP: $SERVER_IP${NC}"
    echo -e "${YELLOW}Revisa y ajusta otras configuraciones en .env si es necesario${NC}"
fi

# Create logs directory
echo -e "${YELLOW}📝 Creando directorio de logs...${NC}"
mkdir -p logs

# Build and start services
echo -e "${YELLOW}🏗️  Construyendo imágenes Docker...${NC}"
docker-compose -f docker-compose.production.yml build

echo -e "${YELLOW}🚀 Iniciando servicios...${NC}"
docker-compose -f docker-compose.production.yml up -d

# Wait for services to start
echo -e "${YELLOW}⏳ Esperando que los servicios inicien...${NC}"
sleep 15

# Check service health
echo -e "${YELLOW}🔍 Verificando estado de los servicios...${NC}"

if docker-compose -f docker-compose.production.yml ps | grep -q "Up"; then
    echo -e "${GREEN}✅ Servicios iniciados correctamente${NC}"
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}🎉 ¡Despliegue completado exitosamente!${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    echo -e "${YELLOW}📋 Información del sistema:${NC}"
    echo -e "🌐 IP del servidor: $SERVER_IP"
    echo -e "📞 Puerto SIP: 5060"
    echo -e "🔧 Puerto Event Socket: 8021"
    echo -e "🎤 Puerto Vosk ASR: 2700"
    
    echo -e "${YELLOW}📱 Configuración para Softphone:${NC}"
    echo -e "   Servidor: $SERVER_IP:5060"
    echo -e "   Usuario: 1001"
    echo -e "   Password: 452910"
    echo -e "   Protocolo: UDP"
    
    echo -e "${YELLOW}🧪 Número de prueba:${NC}"
    echo -e "   Marcar: 77751954340880 (activa detección de buzones)"
    
    echo -e "${YELLOW}📊 Monitoreo:${NC}"
    echo -e "   Logs: docker-compose -f docker-compose.production.yml logs -f"
    echo -e "   fs_cli: docker exec freeswitch-voicemail-detector fs_cli"
    
else
    echo -e "${RED}❌ Error: Algunos servicios no iniciaron correctamente${NC}"
    echo -e "${YELLOW}Mostrando logs para debugging:${NC}"
    docker-compose -f docker-compose.production.yml logs
    exit 1
fi

echo -e "${GREEN}🎯 Sistema listo para detectar buzones de voz!${NC}"