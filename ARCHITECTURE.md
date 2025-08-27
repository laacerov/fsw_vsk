# 🏗️ Arquitectura del Sistema de Detección de Buzones

## 🎯 Objetivo
Sistema inteligente para detectar buzones de voz automáticamente durante llamadas SIP, con capacidad de aprendizaje continuo y clasificación automática.

## 📊 Componentes del Sistema

### 1. **FreeSWITCH + mod_vosk** (Core Engine)
- **Puerto**: 5060 (SIP), 8021 (Event Socket)
- **Función**: Recibir llamadas SIP y procesar audio en tiempo real
- **Módulos clave**: mod_sofia, mod_vosk, mod_event_socket, mod_dptools

### 2. **Servidor Vosk** (ASR Engine)
- **Imagen Docker**: `lacerovasq/voicemail`
- **Puerto**: 2800 (WebSocket)
- **Función**: Reconocimiento de voz especializado en patrones de buzones

### 3. **Base de Datos de Clasificación** (Knowledge Base)
- **Recomendación**: PostgreSQL o MySQL
- **Función**: Almacenar patrones, frases, confianza y resultados de aprendizaje
- **Tablas principales**:
  - `voicemail_patterns` - Patrones de buzones conocidos
  - `detection_logs` - Histórico de detecciones  
  - `learning_queue` - Casos dudosos para validación manual

### 4. **API de Clasificación** (Intelligence Layer)
- **Tecnología**: Python/FastAPI o Node.js
- **Función**: Lógica de decisión y aprendizaje automático
- **Puerto**: 8080

## 🔄 Flujo Detallado del Sistema

### Fase 1: Recepción de Llamada
```
1. Llamada SIP → FreeSWITCH (puerto 5060)
2. FreeSWITCH ejecuta dialplan personalizado
3. Inicia grabación temporal para análisis
4. Activa mod_vosk para transcripción en tiempo real
```

### Fase 2: Análisis ASR en Tiempo Real
```
1. Audio → mod_vosk → lacerovasq/voicemail (WebSocket)
2. Vosk retorna transcripción + metadata
3. FreeSWITCH via Event Socket → API Clasificación
4. API consulta BD para patrones conocidos
```

### Fase 3: Decisión Inteligente
```
1. API calcula score de confianza (0-100%)
2. Si confianza > 85%: BUZÓN CONFIRMADO
3. Si confianza 60-85%: BUZÓN PROBABLE (log para revisión)
4. Si confianza < 60%: LLAMADA NORMAL
```

### Fase 4: Acción y Aprendizaje
```
BUZÓN CONFIRMADO:
├─ Enviar SIP 503 "Service Unavailable - Voicemail Detected"
├─ Registrar en detection_logs
└─ Cortar llamada inmediatamente

BUZÓN PROBABLE:
├─ Continuar llamada (no interrumpir)
├─ Registrar en learning_queue  
└─ Marcar para validación posterior

LLAMADA NORMAL:
└─ Continuar procesamiento normal
```

## 🗄️ Estructura de Base de Datos

### Tabla: voicemail_patterns
```sql
CREATE TABLE voicemail_patterns (
    id SERIAL PRIMARY KEY,
    pattern_text TEXT NOT NULL,
    pattern_type ENUM('greeting', 'beep', 'instruction', 'name'),
    confidence_weight DECIMAL(3,2) DEFAULT 1.00,
    language VARCHAR(5) DEFAULT 'es-ES',
    created_at TIMESTAMP DEFAULT NOW(),
    validated_by VARCHAR(50),
    is_active BOOLEAN DEFAULT true
);
```

### Tabla: detection_logs
```sql
CREATE TABLE detection_logs (
    id SERIAL PRIMARY KEY,
    call_id VARCHAR(100) NOT NULL,
    caller_number VARCHAR(20),
    destination_number VARCHAR(20),
    transcription TEXT,
    confidence_score DECIMAL(5,2),
    detection_result ENUM('voicemail', 'human', 'uncertain'),
    action_taken ENUM('hangup_503', 'continue', 'flag_review'),
    call_duration_seconds INT,
    audio_file_path VARCHAR(255),
    detected_at TIMESTAMP DEFAULT NOW()
);
```

### Tabla: learning_queue
```sql
CREATE TABLE learning_queue (
    id SERIAL PRIMARY KEY,
    detection_log_id INT REFERENCES detection_logs(id),
    transcription TEXT,
    predicted_result VARCHAR(20),
    confidence_score DECIMAL(5,2),
    human_validation VARCHAR(20) NULL, -- 'voicemail', 'human', 'other'
    reviewed_by VARCHAR(50) NULL,
    reviewed_at TIMESTAMP NULL,
    status ENUM('pending', 'validated', 'discarded') DEFAULT 'pending'
);
```

## 🔧 Configuración Técnica

### FreeSWITCH Dialplan (detection_extension.xml)
```xml
<extension name="voicemail_detection">
  <condition field="destination_number" expression="^(.+)$">
    <action application="set" data="call_timeout=30"/>
    <action application="set" data="hangup_after_bridge=true"/>
    <action application="answer"/>
    
    <!-- Iniciar detección ASR -->
    <action application="detect_speech" data="vosk default default"/>
    <action application="lua" data="voicemail_detector.lua"/>
    
    <!-- Playback silencioso para análisis -->
    <action application="playback" data="silence_stream://10000"/>
    
    <!-- Detener detección -->
    <action application="detect_speech" data="stop"/>
  </condition>
</extension>
```

### Configuración mod_vosk (vosk.conf.xml)
```xml
<configuration name="vosk.conf" description="Vosk ASR Configuration">
  <settings>
    <param name="server-url" value="ws://lacerovasq-voicemail:2800"/>
    <param name="return-json" value="1"/>
    <param name="continuous-recognition" value="true"/>
    <param name="interim-results" value="true"/>
    <param name="max-audio-duration" value="15"/>
  </settings>
</configuration>
```

## 🐳 Docker Compose del Sistema Completo

```yaml
services:
  # FreeSWITCH con mod_vosk
  freeswitch:
    build:
      context: ./docker
      dockerfile: Dockerfile.optimized
    container_name: freeswitch-detector
    ports:
      - "5060:5060/udp"
      - "8021:8021/tcp"
    depends_on:
      - vosk-server
      - classification-api
      - postgres
    networks:
      - voicemail-detection

  # Servidor Vosk especializado
  vosk-server:
    image: lacerovasq/voicemail
    container_name: vosk-voicemail
    ports:
      - "2800:2800"
    networks:
      - voicemail-detection

  # API de Clasificación
  classification-api:
    build: ./classification-api
    container_name: classification-api
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgresql://user:pass@postgres:5432/voicemail_db
    depends_on:
      - postgres
    networks:
      - voicemail-detection

  # Base de Datos
  postgres:
    image: postgres:15
    container_name: voicemail-db
    environment:
      - POSTGRES_DB=voicemail_db
      - POSTGRES_USER=voicemail_user
      - POSTGRES_PASSWORD=secure_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./sql/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - voicemail-detection

  # Panel de Administración (Opcional)
  admin-panel:
    build: ./admin-panel
    ports:
      - "3000:3000"
    depends_on:
      - classification-api
    networks:
      - voicemail-detection

volumes:
  postgres_data:

networks:
  voicemail-detection:
    driver: bridge
```

## 📈 Métricas y Monitoreo

### KPIs del Sistema
- **Precisión de detección**: % de buzones correctamente identificados
- **Falsos positivos**: % de llamadas humanas marcadas como buzón  
- **Tiempo de detección**: Segundos hasta identificar buzón
- **Aprendizaje continuo**: Casos validados vs pendientes

### Logs Estructurados
```json
{
  "timestamp": "2024-01-15T10:30:45Z",
  "call_id": "uuid-12345",
  "caller": "+1234567890", 
  "destination": "+0987654321",
  "transcription": "Hola, has llamado a María...",
  "confidence": 92.5,
  "action": "hangup_503",
  "processing_time_ms": 3450
}
```

## 🔄 Proceso de Aprendizaje Continuo

### 1. Recolección Automática
- Todas las detecciones con confianza 60-85% van a learning_queue
- Audio grabado temporalmente para análisis posterior

### 2. Validación Manual
- Interface web para revisar casos dudosos
- Operador marca: "buzón", "humano", "otro"
- Sistema actualiza patrones automáticamente

### 3. Reentrenamiento
- Cada 100 validaciones → actualizar pesos de patrones
- A/B testing de nuevos modelos
- Backup automático de configuraciones

---

**🎯 Este diseño te permitirá:**
- ✅ Detectar buzones con alta precisión
- ✅ Aprender continuamente de nuevos casos  
- ✅ Escalar fácilmente con Docker
- ✅ Monitorear y optimizar el rendimiento
- ✅ Integrar con sistemas existentes via SIP