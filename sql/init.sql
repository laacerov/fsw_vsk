-- Base de Datos para Sistema de Detección de Buzones
-- Inicialización de esquema y datos de ejemplo

-- Crear base de datos
CREATE DATABASE IF NOT EXISTS voicemail_detection;
USE voicemail_detection;

-- Tabla de patrones de buzones de voz
CREATE TABLE voicemail_patterns (
    id SERIAL PRIMARY KEY,
    pattern_text TEXT NOT NULL,
    pattern_type ENUM('greeting', 'beep', 'instruction', 'name', 'company') NOT NULL,
    confidence_weight DECIMAL(3,2) DEFAULT 1.00,
    language VARCHAR(5) DEFAULT 'es-ES',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW() ON UPDATE NOW(),
    validated_by VARCHAR(50),
    validation_count INT DEFAULT 0,
    success_rate DECIMAL(5,2) DEFAULT 0.00,
    is_active BOOLEAN DEFAULT true,
    INDEX idx_pattern_type (pattern_type),
    INDEX idx_language (language),
    INDEX idx_active (is_active)
);

-- Tabla de logs de detección
CREATE TABLE detection_logs (
    id SERIAL PRIMARY KEY,
    call_id VARCHAR(100) NOT NULL UNIQUE,
    caller_number VARCHAR(20),
    destination_number VARCHAR(20),
    call_start_time TIMESTAMP,
    transcription TEXT,
    raw_audio_data JSON,
    confidence_score DECIMAL(5,2),
    detection_result ENUM('voicemail', 'human', 'uncertain', 'timeout') NOT NULL,
    action_taken ENUM('hangup_503', 'hangup_busy', 'continue', 'flag_review') NOT NULL,
    call_duration_seconds INT,
    detection_time_ms INT,
    audio_file_path VARCHAR(255),
    matched_patterns JSON,
    api_response_time_ms INT,
    detected_at TIMESTAMP DEFAULT NOW(),
    INDEX idx_call_id (call_id),
    INDEX idx_caller (caller_number),
    INDEX idx_result (detection_result),
    INDEX idx_detected_at (detected_at)
);

-- Tabla de cola de aprendizaje
CREATE TABLE learning_queue (
    id SERIAL PRIMARY KEY,
    detection_log_id INT NOT NULL,
    transcription TEXT,
    predicted_result VARCHAR(20) NOT NULL,
    confidence_score DECIMAL(5,2),
    audio_snippet_path VARCHAR(255),
    human_validation ENUM('voicemail', 'human', 'ivr', 'other') NULL,
    validation_notes TEXT,
    reviewed_by VARCHAR(50) NULL,
    reviewed_at TIMESTAMP NULL,
    status ENUM('pending', 'validated', 'discarded', 'training') DEFAULT 'pending',
    priority INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (detection_log_id) REFERENCES detection_logs(id) ON DELETE CASCADE,
    INDEX idx_status (status),
    INDEX idx_priority (priority),
    INDEX idx_created_at (created_at)
);

-- Tabla de configuración del sistema
CREATE TABLE system_config (
    id INT PRIMARY KEY AUTO_INCREMENT,
    config_key VARCHAR(100) NOT NULL UNIQUE,
    config_value TEXT NOT NULL,
    config_type ENUM('string', 'number', 'boolean', 'json') DEFAULT 'string',
    description TEXT,
    updated_at TIMESTAMP DEFAULT NOW() ON UPDATE NOW(),
    updated_by VARCHAR(50)
);

-- Tabla de estadísticas por día
CREATE TABLE daily_stats (
    date DATE PRIMARY KEY,
    total_calls INT DEFAULT 0,
    voicemail_detected INT DEFAULT 0,
    human_detected INT DEFAULT 0,
    uncertain_cases INT DEFAULT 0,
    false_positives INT DEFAULT 0,
    false_negatives INT DEFAULT 0,
    avg_confidence DECIMAL(5,2),
    avg_detection_time_ms INT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW() ON UPDATE NOW()
);

-- Insertar patrones de ejemplo en español
INSERT INTO voicemail_patterns (pattern_text, pattern_type, confidence_weight, language) VALUES
-- Saludos típicos de buzón
('hola has llamado', 'greeting', 0.95, 'es-ES'),
('buenas has contactado', 'greeting', 0.90, 'es-ES'),
('gracias por llamar', 'greeting', 0.88, 'es-ES'),
('bienvenido al buzón', 'greeting', 0.98, 'es-ES'),
('has llegado al buzón de voz', 'greeting', 0.99, 'es-ES'),

-- Nombres típicos en buzones
('soy maría', 'name', 0.75, 'es-ES'),
('habla juan', 'name', 0.75, 'es-ES'),
('mi nombre es', 'name', 0.70, 'es-ES'),

-- Instrucciones de buzón  
('deja tu mensaje', 'instruction', 0.85, 'es-ES'),
('después del tono', 'instruction', 0.90, 'es-ES'),
('tras la señal', 'instruction', 0.90, 'es-ES'),
('luego del pitido', 'instruction', 0.88, 'es-ES'),
('después del beep', 'instruction', 0.85, 'es-ES'),

-- Sonidos característicos
('beep', 'beep', 0.95, 'es-ES'),
('tono', 'beep', 0.80, 'es-ES'),
('pitido', 'beep', 0.85, 'es-ES'),

-- Empresas/Organizaciones
('empresa', 'company', 0.70, 'es-ES'),
('compañía', 'company', 0.70, 'es-ES'),
('oficina', 'company', 0.65, 'es-ES'),
('departamento', 'company', 0.60, 'es-ES');

-- Configuración inicial del sistema
INSERT INTO system_config (config_key, config_value, config_type, description) VALUES
('confidence_threshold_high', '85.0', 'number', 'Umbral de confianza alta para confirmación automática'),
('confidence_threshold_low', '60.0', 'number', 'Umbral de confianza baja para aprendizaje'),
('max_detection_time_seconds', '15', 'number', 'Tiempo máximo para detección antes de timeout'),
('enable_learning_mode', 'true', 'boolean', 'Activar modo de aprendizaje automático'),
('sip_error_code', '503', 'string', 'Código SIP a enviar cuando se detecta buzón'),
('sip_error_message', 'Service Unavailable - Voicemail Detected', 'string', 'Mensaje de error SIP'),
('audio_recording_enabled', 'true', 'boolean', 'Grabar audio para análisis posterior'),
('vosk_server_url', 'ws://vosk-voicemail:2800', 'string', 'URL del servidor Vosk'),
('classification_api_url', 'http://classification-api:8080', 'string', 'URL de la API de clasificación');

-- Crear vista para estadísticas de rendimiento
CREATE VIEW detection_performance AS
SELECT 
    DATE(detected_at) as date,
    COUNT(*) as total_detections,
    COUNT(CASE WHEN detection_result = 'voicemail' THEN 1 END) as voicemail_count,
    COUNT(CASE WHEN detection_result = 'human' THEN 1 END) as human_count,
    COUNT(CASE WHEN detection_result = 'uncertain' THEN 1 END) as uncertain_count,
    AVG(confidence_score) as avg_confidence,
    AVG(detection_time_ms) as avg_detection_time_ms,
    AVG(call_duration_seconds) as avg_call_duration
FROM detection_logs 
GROUP BY DATE(detected_at)
ORDER BY date DESC;

-- Crear vista para patrones más efectivos
CREATE VIEW pattern_effectiveness AS
SELECT 
    vp.id,
    vp.pattern_text,
    vp.pattern_type,
    vp.confidence_weight,
    COUNT(dl.id) as usage_count,
    AVG(dl.confidence_score) as avg_confidence_when_used,
    (COUNT(CASE WHEN dl.detection_result = 'voicemail' THEN 1 END) * 100.0 / COUNT(dl.id)) as success_rate
FROM voicemail_patterns vp
LEFT JOIN detection_logs dl ON JSON_CONTAINS(dl.matched_patterns, JSON_QUOTE(vp.pattern_text))
WHERE vp.is_active = true
GROUP BY vp.id
ORDER BY success_rate DESC, usage_count DESC;

-- Procedimiento para actualizar estadísticas diarias
DELIMITER //
CREATE PROCEDURE UpdateDailyStats(IN target_date DATE)
BEGIN
    INSERT INTO daily_stats (
        date, total_calls, voicemail_detected, human_detected, 
        uncertain_cases, avg_confidence, avg_detection_time_ms
    )
    SELECT 
        target_date,
        COUNT(*),
        COUNT(CASE WHEN detection_result = 'voicemail' THEN 1 END),
        COUNT(CASE WHEN detection_result = 'human' THEN 1 END),
        COUNT(CASE WHEN detection_result = 'uncertain' THEN 1 END),
        AVG(confidence_score),
        AVG(detection_time_ms)
    FROM detection_logs 
    WHERE DATE(detected_at) = target_date
    ON DUPLICATE KEY UPDATE
        total_calls = VALUES(total_calls),
        voicemail_detected = VALUES(voicemail_detected),
        human_detected = VALUES(human_detected),
        uncertain_cases = VALUES(uncertain_cases),
        avg_confidence = VALUES(avg_confidence),
        avg_detection_time_ms = VALUES(avg_detection_time_ms),
        updated_at = NOW();
END //
DELIMITER ;

-- Crear índices para mejor rendimiento
CREATE INDEX idx_detection_logs_composite ON detection_logs(detected_at, detection_result, confidence_score);
CREATE INDEX idx_learning_queue_priority ON learning_queue(status, priority, created_at);

-- Crear trigger para mantener estadísticas actualizadas
DELIMITER //
CREATE TRIGGER after_detection_insert
AFTER INSERT ON detection_logs
FOR EACH ROW
BEGIN
    CALL UpdateDailyStats(DATE(NEW.detected_at));
END //
DELIMITER ;

-- Insertar estadística inicial
INSERT INTO daily_stats (date) VALUES (CURDATE());

COMMIT;