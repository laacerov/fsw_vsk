# 🚀 Guía de Despliegue - Sistema de Detección de Buzones

## 📋 Resumen del Sistema

Tu sistema implementa **detección automática de buzones de voz** con las siguientes características:

### ✅ **Flujo Validado:**
1. **Llamada SIP** → FreeSWITCH (puerto 5060)
2. **Análisis ASR** → mod_vosk + lacerovasq/voicemail  
3. **Clasificación IA** → API Python con base de datos
4. **Decisión automática:**
   - Si **confianza ≥ 85%** → **SIP 503** + cortar llamada
   - Si **confianza 60-85%** → continuar + marcar para aprendizaje
   - Si **confianza < 60%** → continuar normalmente

### 🎯 **Código de Error Personalizado:**
```
SIP/2.0 503 Service Unavailable
Reason: Voicemail Detected - Automated Rejection
```

## 🏗️ Arquitectura del Sistema

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Llamada SIP   │───▶│   FreeSWITCH    │───▶│   Vosk Server   │
│                 │    │   + mod_vosk    │    │ lacerovasq/vm   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                               │                       │
                               ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Base de Datos   │◀───│ Classification  │◀───│  Transcription  │
│   PostgreSQL    │    │      API        │    │     Results     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│  Learning AI    │    │   SIP Response  │
│   (Feedback)    │    │  503/Continue   │
└─────────────────┘    └─────────────────┘
```

## 🚀 Despliegue Paso a Paso

### 1. **Preparación del Entorno**
```bash
# Clonar configuraciones
git clone <tu-repo>
cd fsw_vsk/

# Crear directorios necesarios
mkdir -p audio_temp api_logs admin_logs worker_logs
mkdir -p nginx/ssl monitoring/

# Dar permisos
chmod 755 scripts/lua/*.lua
chmod 644 conf/dialplan/default/*.xml
```

### 2. **Configuración de Variables**
Crear `.env` file:
```bash
# Database
POSTGRES_DB=voicemail_detection
POSTGRES_USER=voicemail_user
POSTGRES_PASSWORD=your_secure_password

# API Configuration
CONFIDENCE_THRESHOLD_HIGH=85.0
CONFIDENCE_THRESHOLD_LOW=60.0
DEBUG_MODE=true

# Vosk Configuration  
VOSK_SERVER_URL=ws://vosk-voicemail:2800

# Security
FS_CLI_PASSWORD=your_fs_password
ADMIN_PASSWORD=your_admin_password
```

### 3. **Despliegue Básico**
```bash
# Construir servicios principales
docker-compose -f docker-compose.full-system.yml build

# Levantar sistema completo
docker-compose -f docker-compose.full-system.yml up -d

# Verificar servicios
docker-compose -f docker-compose.full-system.yml ps
```

### 4. **Verificación de Servicios**

#### FreeSWITCH Status
```bash
# Conectar a fs_cli
docker exec -it freeswitch-detector fs_cli

# Verificar módulos cargados
fs> show modules | grep vosk
fs> module_exists mod_event_socket
fs> sofia status
```

#### Base de Datos
```bash
# Conectar a PostgreSQL
docker exec -it voicemail-db psql -U voicemail_user -d voicemail_detection

# Verificar tablas
\dt
SELECT COUNT(*) FROM voicemail_patterns;
SELECT * FROM system_config;
```

#### API de Clasificación
```bash
# Test API
curl -X POST http://localhost:8080/classify \
  -H "Content-Type: application/json" \
  -d '{"transcription": "hola has llamado a maria deja tu mensaje", "call_id": "test-123"}'
```

### 5. **Configuración de Producción**

#### SSL/TLS (Recomendado)
```bash
# Generar certificados SSL
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/voicemail.key \
  -out nginx/ssl/voicemail.crt

# Actualizar nginx.conf con SSL
```

#### Backup Automático
```bash
# Script de backup diario
cat > backup.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
docker exec voicemail-db pg_dump -U voicemail_user voicemail_detection > backup_$DATE.sql
EOF

# Programar en crontab
0 2 * * * /path/to/backup.sh
```

## 📊 Monitoreo y Métricas

### Dashboard Principal
Acceder a: `http://localhost:3000`

### Métricas Clave
- **Precisión de Detección**: % de aciertos
- **Falsos Positivos**: Humanos marcados como buzón
- **Tiempo de Detección**: Promedio en segundos
- **Throughput**: Llamadas procesadas/hora

### Logs Importantes
```bash
# FreeSWITCH logs
docker logs freeswitch-detector | grep "VOICEMAIL_DETECTOR"

# API logs
docker logs classification-api | grep "confidence"

# Database performance
docker logs voicemail-db | grep "slow query"
```

## 🔧 Configuración Avanzada

### 1. **Ajustar Umbrales de Confianza**
```sql
-- Actualizar configuración en BD
UPDATE system_config 
SET config_value = '90.0' 
WHERE config_key = 'confidence_threshold_high';

UPDATE system_config 
SET config_value = '70.0' 
WHERE config_key = 'confidence_threshold_low';
```

### 2. **Agregar Nuevos Patrones**
```sql
-- Insertar patrones personalizados
INSERT INTO voicemail_patterns (pattern_text, pattern_type, confidence_weight, language) 
VALUES 
('bienvenido al contestador', 'greeting', 0.92, 'es-ES'),
('no puedo atender ahora', 'greeting', 0.88, 'es-ES'),
('oficina cerrada', 'company', 0.85, 'es-ES');
```

### 3. **Configurar Números de Prueba**
```xml
<!-- En dialplan: test_numbers.xml -->
<extension name="test_voicemail_detection">
  <condition field="destination_number" expression="^(9999)$">
    <action application="playback" data="/usr/local/freeswitch/sounds/voicemail_sample.wav"/>
    <action application="transfer" data="${destination_number} XML default"/>
  </condition>
</extension>
```

## 🧪 Testing y Validación

### Test Cases
```bash
# 1. Llamada a número de prueba (debe detectar buzón)
sip:9999@your-freeswitch-ip

# 2. Verificar logs
docker logs freeswitch-detector | tail -50

# 3. Verificar BD
docker exec -it voicemail-db psql -U voicemail_user -d voicemail_detection \
  -c "SELECT * FROM detection_logs ORDER BY detected_at DESC LIMIT 5;"
```

### Casos de Prueba Típicos
1. **Buzón Personal**: "Hola, has llamado a María..."
2. **Buzón Empresarial**: "Gracias por llamar a XYZ Company..."  
3. **IVR**: "Para ventas marque 1, para soporte marque 2..."
4. **Humano**: Conversación normal
5. **Ruido**: Llamadas con mala calidad

## 📈 Optimización y Escalabilidad

### Performance Tips
```yaml
# Optimizaciones en docker-compose
services:
  freeswitch:
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '1.0'
    ulimits:
      nofile: 65536
```

### Escalabilidad Horizontal
```bash
# Múltiples instancias de API
docker-compose up --scale classification-api=3
```

### Cache Redis
```python
# En la API, usar Redis para cachear patrones frecuentes
import redis
cache = redis.Redis(host='redis', port=6379, db=0)
```

## 🔍 Troubleshooting

### Problema: FreeSWITCH no carga mod_vosk
```bash
# Verificar dependencias
docker exec freeswitch-detector ldd /usr/local/freeswitch/mod/mod_vosk.so

# Verificar configuración
docker exec freeswitch-detector cat /usr/local/freeswitch/conf/autoload_configs/vosk.conf.xml
```

### Problema: API no responde
```bash
# Verificar conectividad
docker exec freeswitch-detector curl -v http://classification-api:8080/health

# Verificar logs
docker logs classification-api --tail 100
```

### Problema: Base de datos lenta
```sql
-- Verificar índices
\d+ detection_logs
-- Recrear índices si es necesario
REINDEX TABLE detection_logs;
```

## 🎯 Métricas de Éxito

### Objetivos de Rendimiento
- **Precisión > 90%** en detección de buzones
- **Falsos positivos < 5%**
- **Tiempo detección < 10 segundos**
- **Uptime > 99.9%**

### KPIs Mensuales
- Total llamadas procesadas
- % de buzones detectados
- % de aprendizaje aplicado
- Mejora en precisión mes a mes

---

## 🎉 ¡Sistema Listo para Producción!

Con esta configuración tienes un **sistema completo de detección de buzones** que:

✅ **Detecta automáticamente** buzones con alta precisión  
✅ **Aprende continuamente** de nuevos casos  
✅ **Escala horizontalmente** según demanda  
✅ **Monitorea rendimiento** en tiempo real  
✅ **Mantiene logs detallados** para auditoría  

**Tu flujo está perfectamente implementado: SIP → Análisis → IA → Decisión → Error 503**