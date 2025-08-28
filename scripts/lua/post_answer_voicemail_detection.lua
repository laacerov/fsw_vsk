--[[
FreeSWITCH Post-Answer Voicemail Detection
Se ejecuta INMEDIATAMENTE después de que la llamada saliente sea respondida
Analiza los primeros 3 segundos para detectar buzones de voz
]]

-- Configuración
local config = {
    detection_timeout = 3,        -- 3 segundos exactos
    confidence_threshold = 85.0,  -- 85% confianza para confirmar buzón
    sample_rate = 8000,          -- 8kHz standard para telefonía
    debug_mode = true
}

local function log_message(level, message)
    if config.debug_mode or level ~= "DEBUG" then
        freeswitch.consoleLog(level, "[POST_ANSWER_VM] " .. message .. "\n")
    end
end

-- Función principal de detección post-answer
local function detect_voicemail_post_answer()
    local session = freeswitch.Session()
    
    if not session:ready() then
        log_message("ERROR", "Sesión no está lista para detección")
        return
    end
    
    -- Información de la llamada
    local call_uuid = session:getVariable("uuid")
    local destination = session:getVariable("destination_number") or "unknown"
    local caller = session:getVariable("caller_id_number") or "unknown"
    
    log_message("INFO", "=== DETECCIÓN POST-ANSWER INICIADA ===")
    log_message("INFO", "Call-ID: " .. call_uuid)
    log_message("INFO", "Caller: " .. caller)
    log_message("INFO", "Destination: " .. destination)
    log_message("INFO", "Timeout: " .. config.detection_timeout .. " segundos")
    
    -- Marcar inicio de detección
    local detection_start = os.time()
    session:setVariable("detection_start_time", tostring(detection_start))
    
    -- Iniciar ASR con Vosk inmediatamente
    log_message("INFO", "Iniciando ASR Vosk...")
    session:execute("detect_speech", "vosk default default")
    
    -- Variables para acumular datos
    local transcription = ""
    local confidence_scores = {}
    local speech_events = 0
    
    -- Bucle de detección durante exactamente 3 segundos
    log_message("INFO", "Analizando audio por " .. config.detection_timeout .. " segundos...")
    
    while session:ready() do
        local current_time = os.time()
        local elapsed_time = current_time - detection_start
        
        -- TIMEOUT ESTRICTO - Exactamente 3 segundos
        if elapsed_time >= config.detection_timeout then
            log_message("INFO", "Timeout alcanzado - Finalizando análisis")
            break
        end
        
        -- Verificar si hay nuevos eventos de speech
        session:sleep(100) -- Verificar cada 100ms
        
        -- Obtener resultado de Vosk (esto necesita implementarse según la API real)
        local speech_result = get_vosk_result(session)
        
        if speech_result and speech_result ~= "" then
            transcription = transcription .. " " .. speech_result
            speech_events = speech_events + 1
            log_message("DEBUG", "Speech #" .. speech_events .. ": " .. speech_result)
            
            -- Análisis en tiempo real cada 500ms
            if elapsed_time > 0.5 then
                local vm_confidence = analyze_realtime_patterns(transcription)
                table.insert(confidence_scores, vm_confidence)
                
                log_message("DEBUG", "Confianza actual: " .. vm_confidence .. "%")
                
                -- Si tenemos alta confianza de buzón, cortar inmediatamente
                if vm_confidence >= config.confidence_threshold then
                    log_message("WARNING", "=== BUZÓN CONFIRMADO - CORTANDO INMEDIATAMENTE ===")
                    log_message("INFO", "Transcripción: '" .. transcription .. "'")
                    log_message("INFO", "Confianza final: " .. vm_confidence .. "%")
                    log_message("INFO", "Tiempo detección: " .. elapsed_time .. " segundos")
                    
                    -- Establecer variables de resultado
                    session:setVariable("detection_result", "voicemail")
                    session:setVariable("detection_confidence", tostring(vm_confidence))
                    session:setVariable("transcription_text", transcription)
                    session:setVariable("detection_time", tostring(elapsed_time))
                    
                    -- Detener ASR
                    session:execute("detect_speech", "stop")
                    
                    -- Registrar en base de datos antes de cortar
                    log_detection_result("voicemail", vm_confidence, transcription, elapsed_time)
                    
                    -- CORTAR LLAMADA CON ERROR 503
                    log_message("INFO", "Enviando 503 Service Unavailable")
                    session:hangup("CALL_REJECTED")
                    
                    return -- Salir inmediatamente
                end
            end
        end
        
        -- Verificar que la llamada siga activa
        if not session:ready() then
            log_message("WARNING", "Llamada terminada durante detección")
            break
        end
    end
    
    -- Detener ASR
    session:execute("detect_speech", "stop")
    
    -- Si llegamos aquí sin detectar buzón
    local final_confidence = 0
    if #confidence_scores > 0 then
        -- Calcular confianza promedio
        local sum = 0
        for _, score in ipairs(confidence_scores) do
            sum = sum + score
        end
        final_confidence = sum / #confidence_scores
    end
    
    if speech_events > 0 then
        log_message("INFO", "=== ANÁLISIS COMPLETADO - HUMANO DETECTADO ===")
        log_message("INFO", "Eventos speech: " .. speech_events)
        log_message("INFO", "Transcripción final: '" .. transcription .. "'")
        log_message("INFO", "Confianza buzón: " .. final_confidence .. "% (< " .. config.confidence_threshold .. "%)")
        
        -- Establecer variables
        session:setVariable("detection_result", "human")
        session:setVariable("detection_confidence", tostring(100 - final_confidence))
        session:setVariable("transcription_text", transcription)
        
        -- Registrar resultado humano
        log_detection_result("human", 100 - final_confidence, transcription, config.detection_timeout)
    else
        log_message("INFO", "=== SIN SPEECH DETECTADO - ASUMIENDO HUMANO ===")
        
        session:setVariable("detection_result", "no_speech")
        session:setVariable("detection_confidence", "50")
        
        log_detection_result("no_speech", 50, "", config.detection_timeout)
    end
    
    log_message("INFO", "=== DETECCIÓN FINALIZADA - LLAMADA CONTINÚA ===")
end

-- Función para analizar patrones en tiempo real
function analyze_realtime_patterns(text)
    if not text or text == "" then
        return 0
    end
    
    local text_lower = string.lower(text)
    local confidence = 0
    
    -- Patrones de alta confianza (indicadores fuertes de buzón)
    local high_confidence_patterns = {
        ["buzon de voz"] = 90,
        ["deja tu mensaje"] = 95,
        ["despues del tono"] = 90,
        ["tras la señal"] = 90,  
        ["no puedo atender"] = 85,
        ["gracias por llamar"] = 80,
        ["hola has llamado"] = 85,
        ["no estoy disponible"] = 85
    }
    
    -- Patrones de confianza media
    local medium_confidence_patterns = {
        ["buzon"] = 70,
        ["mensaje"] = 60,
        ["tono"] = 65,
        ["beep"] = 80,
        ["pitido"] = 75,
        ["señal"] = 65
    }
    
    -- Verificar patrones de alta confianza
    for pattern, score in pairs(high_confidence_patterns) do
        if string.find(text_lower, pattern) then
            confidence = math.max(confidence, score)
            log_message("DEBUG", "Patrón HIGH encontrado: '" .. pattern .. "' -> " .. score .. "%")
        end
    end
    
    -- Verificar patrones de confianza media si no hay alta confianza
    if confidence < 80 then
        for pattern, score in pairs(medium_confidence_patterns) do
            if string.find(text_lower, pattern) then
                confidence = math.max(confidence, score)
                log_message("DEBUG", "Patrón MEDIUM encontrado: '" .. pattern .. "' -> " .. score .. "%")
            end
        end
    end
    
    -- Bonus por combinaciones de patrones
    if string.find(text_lower, "mensaje") and string.find(text_lower, "tono") then
        confidence = confidence + 15
        log_message("DEBUG", "Bonus combinación 'mensaje + tono': +15%")
    end
    
    return math.min(confidence, 100)
end

-- Función para obtener resultado de Vosk (placeholder)
function get_vosk_result(session)
    -- Esta función debe implementarse según la integración real con Vosk
    -- Por ahora retornamos resultado simulado basado en variables de sesión
    local result = session:getVariable("detect_speech_result")
    if result then
        session:setVariable("detect_speech_result", "") -- Limpiar para próxima lectura
        return result
    end
    return nil
end

-- Función para registrar resultado de detección
function log_detection_result(result, confidence, transcription, duration)
    log_message("INFO", "Registrando resultado: " .. result .. " (" .. confidence .. "%, " .. duration .. "s)")
    -- Aquí se implementaría la conexión a base de datos
    -- Por ahora solo registramos en logs
end

-- EJECUTAR DETECCIÓN
log_message("INFO", "=== POST-ANSWER VOICEMAIL DETECTOR INICIADO ===")
detect_voicemail_post_answer()
log_message("INFO", "=== POST-ANSWER DETECTOR FINALIZADO ===")