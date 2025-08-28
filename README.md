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
curl -sSL https://raw.githubusercontent.com/laacerov/freeswitch-voicemail-detection/main/deploy.sh | bash
```

### Opción 2: Manual
```bash
# Clonar repositorio
git clone https://github.com/laacerov/freeswitch-voicemail-detection.git
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

### 🔥 Flujo de Detección Post-Conexión

El sistema implementa detección **DESPUÉS** de establecer la llamada:

1. **📞 Llamada saliente** con prefijo `77751XXXXXXXX`
2. **🔗 Bridge inmediato** al gateway `172.16.250.197`  
3. **⚡ Detección automática** en los **primeros 3 segundos** post-answer
4. **🛑 Corte inmediato** con error `503` si detecta buzón de voz
5. **✅ Continúa normal** si detecta humano

### 1. Gateway Configuration
```xml
<!-- conf/sip_profiles/external/voicemail_detection_gw.xml -->
<gateway name="voicemail_detection_gw">
  <param name="proxy" value="172.16.250.197"/>
  <param name="username" value="77751"/>
  <param name="password" value="77751"/>
  <param name="register" value="false"/>
</gateway>
```

### 2. Dialplan para Llamadas Salientes
```xml
<!-- conf/dialplan/default/outbound_voicemail_detection.xml -->
<extension name="outbound_voicemail_detection">
  <condition field="destination_number" expression="^(77751)(\d{7,15})$">
    <!-- Configurar detección post-answer -->
    <action application="set" data="execute_on_answer=lua post_answer_voicemail_detection.lua"/>
    
    <!-- Bridge directo al gateway -->
    <action application="bridge" data="sofia/gateway/voicemail_detection_gw/${destination_clean}"/>
  </condition>
</extension>
```

### 3. Script Post-Answer Detection
```lua
-- scripts/lua/post_answer_voicemail_detection.lua
-- ✅ Análisis exacto de 3 segundos
-- ✅ Patrones optimizados en español  
-- ✅ Corte inmediato con 503 si detecta buzón
-- ✅ Continúa si detecta humano
local config = {
    detection_timeout = 3,        -- 3 segundos exactos
    confidence_threshold = 85.0,  -- 85% confianza mínima
}
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

## 🎙️ Casos de Uso Principales

### 🎯 Detección de Buzones en Llamadas Salientes
- **Análisis post-conexión** en primeros 3 segundos
- **Corte automático** con error 503 si detecta buzón
- **Optimización de costos** en campañas outbound
- **Reducción de tiempo** perdido en buzones

### 📊 Casos Secundarios  
1. **Transcripción en tiempo real de llamadas** 
2. **Análisis de patrones de audio**
3. **Sistemas IVR inteligentes**
4. **Monitoreo de calidad de llamadas**

## 🧪 Pruebas del Sistema

### Configuración de Softphone
```bash
Servidor: YOUR_SERVER_IP:5060
Usuario: 1001  
Password: 1001
Protocolo: UDP
```

### Números de Prueba
```bash
# Llamar desde softphone registrado como 1001:
77751123456789  # Se conecta al gateway 172.16.250.197
                # Activa detección automática post-answer
                # Corta si detecta buzón en 3 segundos

# Números locales de prueba (simulan buzones):
777519999       # Simula buzón típico
777518888       # Simula buzón corporativo  
777517777       # Simula buzón personal
```

### Monitoreo en Tiempo Real
```bash
# Ver logs de detección
docker logs -f freeswitch

# Conectar a fs_cli para debug
docker exec -it freeswitch fs_cli

# Verificar gateway
freeswitch> sofia status gateway voicemail_detection_gw
```

## ⚡ Optimizaciones Incluidas

### 🏗️ Build Optimizations
- ✅ Compilación en paralelo (`-j$(nproc)`)
- ✅ Dependencias mínimas necesarias  
- ✅ Módulos compilados individualmente
- ✅ Cache de librerías optimizado
- ✅ **mod_dialplan_xml compilado manualmente** (fix crítico)

### 🚀 Runtime Optimizations  
- ✅ **Detección post-answer** (no pre-conexión)
- ✅ **Timeout exacto de 3 segundos**
- ✅ **Corte inmediato** si detecta buzón
- ✅ **Patrones optimizados** para español
- ✅ **Event-driven** sin polling innecesario

### 🔧 Infrastructure
- ✅ Configuración de puertos específica
- ✅ Reinicio automático del contenedor
- ✅ Gateway pre-configurado para 172.16.250.197
- ✅ Autorización con prefijo 77751

---

**🎉 Tu FreeSWITCH con mod_vosk está listo para detectar buzones de voz!** 

Para soporte técnico, revisa los logs con `docker logs freeswitch-vosk` o conecta con `fs_cli` para debugging interactivo.