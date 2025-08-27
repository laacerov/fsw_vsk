# 🎯 FreeSWITCH Voicemail Detection System

Sistema avanzado de detección de buzones de voz usando FreeSWITCH con ASR (Automatic Speech Recognition) basado en Vosk. Detecta automáticamente buzones de voz en llamadas salientes y termina la conexión para optimizar costos y recursos.

## 🌟 Características

- ✅ **Detección automática** de buzones de voz en tiempo real
- ✅ **ASR con Vosk** para reconocimiento de voz en español
- ✅ **Gateway saliente** configurable para llamadas a través de carriers
- ✅ **Análisis de patrones** inteligente para clasificar buzones vs humanos
- ✅ **Sistema de aprendizaje** mediante base de datos de patrones
- ✅ **Logs detallados** para monitoreo y debugging
- ✅ **Fácil despliegue** con Docker Compose
- ✅ **Escalable** para múltiples llamadas simultáneas

## 📦 Módulos Instalados

```
mod_vosk.so         - Motor ASR principal (91KB)
mod_event_socket.so - Control externo (254KB) 
mod_sofia.so        - Protocolo SIP (10.5MB)
mod_dptools.so      - Herramientas dialplan (588KB)
mod_console.so      - Logging (99KB)
mod_abstraction.so  - Abstracción (70KB)
```

## 🏗️ Arquitectura

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Softphone     │───▶│   FreeSWITCH     │───▶│  Gateway SIP    │
│   (Zoiper)      │    │  + mod_vosk      │    │ (172.16.250.197)│
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │   Vosk ASR       │
                       │   Server         │
                       │  (Puerto 2700)   │
                       └──────────────────┘
```

## 📋 Requisitos

- **Docker** 20.10+
- **Docker Compose** 2.0+
- **Linux Server** (Ubuntu 20.04+ recomendado)
- **4GB RAM** mínimo
- **2 CPU cores** mínimo
- **10GB espacio** en disco

## 🚀 Instalación Rápida

### Opción 1: Script Automático
```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/freeswitch-voicemail-detection/main/deploy.sh | bash
```

### Opción 2: Manual
```bash
# Clonar repositorio
git clone https://github.com/YOUR_USERNAME/freeswitch-voicemail-detection.git
cd freeswitch-voicemail-detection

# Configurar variables de entorno
cp .env.example .env
nano .env  # Ajustar IP_EXTERNA y configuraciones

# Desplegar
docker-compose -f docker-compose.production.yml up -d
```

## 🔧 Pruebas y Validación

### Verificar módulos cargados
```bash
# Conectar a fs_cli
docker exec -it freeswitch-vosk fs_cli

# Dentro de fs_cli verificar módulos
freeswitch@local> module_exists mod_vosk
freeswitch@local> module_exists mod_event_socket  
freeswitch@local> show modules | grep vosk
```

### Verificar configuración ASR
```bash
# Ver configuración de mod_vosk
freeswitch@local> vosk status

# Listar interfaces ASR disponibles
freeswitch@local> show asr
```

## 📋 Configuración para Detección de Buzones

### 1. Configurar servidor Vosk
Editar `conf/autoload_configs/vosk.conf.xml`:
```xml
<configuration name="vosk.conf" description="Vosk ASR Configuration">
  <settings>
    <param name="server-url" value="ws://YOUR_VOSK_SERVER:2800"/>
    <param name="return-json" value="1"/>
  </settings>
</configuration>
```

### 2. Dialplan para detección
Ejemplo en `conf/dialplan/default/voicemail_detect.xml`:
```xml
<extension name="voicemail_detection">
  <condition field="destination_number" expression="^(detect_vm)$">
    <action application="answer"/>
    <action application="detect_speech" data="vosk default default"/>
    <action application="playback" data="silence_stream://30000"/>
    <action application="detect_speech" data="resume"/>
    <!-- Lógica de detección de patrones de buzón -->
  </condition>
</extension>
```

## 🐳 Estructura del Proyecto

```
fsw_vsk/
├── docker/
│   ├── Dockerfile.optimized      # Dockerfile mejorado
│   ├── Dockerfile               # Dockerfile original  
│   └── modules.conf             # Configuración módulos
├── conf/                        # Configuración FreeSWITCH
│   ├── autoload_configs/
│   │   ├── vosk.conf.xml       # Configuración mod_vosk
│   │   └── modules.conf.xml    # Módulos a cargar
│   └── dialplan/               # Lógica de llamadas
├── docker-compose.optimized.yml # Docker Compose optimizado
├── docker-compose.yml          # Docker Compose original
└── README.md                   # Esta documentación
```

## 🔍 Solución de Problemas

### FreeSWITCH no inicia
```bash
# Ver logs del contenedor
docker logs freeswitch-vosk

# Conectar al contenedor para debug
docker exec -it freeswitch-vosk bash
```

### fs_cli no conecta
```bash
# Verificar que el puerto Event Socket esté abierto
docker exec freeswitch-vosk netstat -tulpn | grep 8021

# Probar conexión directa
docker exec freeswitch-vosk fs_cli -H 127.0.0.1 -P 8021 -p ClueCon
```

### mod_vosk no carga
```bash
# Verificar dependencias
docker exec freeswitch-vosk ldd /usr/local/freeswitch/mod/mod_vosk.so

# Verificar configuración
docker exec freeswitch-vosk cat /usr/local/freeswitch/conf/autoload_configs/vosk.conf.xml
```

## 📊 Rendimiento

- **Tiempo de build**: ~15-20 minutos
- **Tamaño imagen**: ~4GB
- **RAM requerida**: Mínimo 2GB, recomendado 4GB
- **CPU**: Funciona en sistemas x86_64

## 🎙️ Casos de Uso

1. **Detección automática de buzones de voz**
2. **Transcripción en tiempo real de llamadas** 
3. **Análisis de patrones de audio**
4. **Sistemas IVR inteligentes**
5. **Monitoreo de calidad de llamadas**

## ⚡ Optimizaciones Incluidas

- ✅ Compilación en paralelo (`-j$(nproc)`)
- ✅ Dependencias mínimas necesarias  
- ✅ Módulos compilados individualmente
- ✅ Cache de librerías optimizado
- ✅ Configuración de puertos específica
- ✅ Reinicio automático del contenedor

---

**🎉 Tu FreeSWITCH con mod_vosk está listo para detectar buzones de voz!** 

Para soporte técnico, revisa los logs con `docker logs freeswitch-vosk` o conecta con `fs_cli` para debugging interactivo.