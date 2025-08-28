--[[
FreeSWITCH Event Socket Handler: Bridge Voicemail Detection
Se ejecuta cuando se establece un bridge y activa detección ASR
]]

-- Configuración
local config = {
    detection_timeout = 3, -- 3 segundos
    confidence_threshold = 85.0,
    vosk_server = "ws://vosk-voicemail:2800",
    debug_mode = true
}

local function log_message(level, message)
    if config.debug_mode or level ~= "DEBUG" then
        freeswitch.consoleLog(level, "[BRIDGE_VM_DETECTOR] " .. message .. "\n")
    end
end

-- Función principal que maneja eventos de bridge
local function handle_bridge_event()
    
    -- Conectar al Event Socket
    local event_socket = freeswitch.EventConsumer("CHANNEL_BRIDGE")
    
    if not event_socket then
        log_message("ERROR", "No se pudo conectar al Event Socket")
        return
    end
    
    log_message("INFO", "=== Bridge Voicemail Detector iniciado ===")
    
    -- Escuchar eventos de bridge
    while true do
        local event = event_socket:pop(1000) -- 1 segundo timeout
        
        if event then
            local event_name = event:getHeader("Event-Name")
            local call_uuid = event:getHeader("Unique-ID")
            local vm_detection_enabled = event:getHeader("variable_voicemail_detection")
            
            if event_name == "CHANNEL_BRIDGE" and vm_detection_enabled == "true" then
                log_message("INFO", "=== BRIDGE ESTABLECIDO - Iniciando detección ===")
                log_message("INFO", "Call-ID: " .. (call_uuid or "unknown"))
                
                -- Iniciar detección ASR inmediatamente después del bridge
                start_voicemail_detection(call_uuid)
            end
        end
    end
end

-- Función para iniciar detección de buzones post-bridge
local function start_voicemail_detection(call_uuid)
    if not call_uuid then
        log_message("ERROR", "No se proporcionó Call-ID para detección")
        return
    end
    
    log_message("INFO", "Iniciando ASR para Call-ID: " .. call_uuid)
    
    -- Obtener sesión de la llamada
    local session = freeswitch.Session(call_uuid)
    if not session:ready() then
        log_message("WARNING", "Sesión no disponible para detección")
        return
    end
    
    -- Iniciar ASR con Vosk
    session:execute("detect_speech", "vosk default default")
    session:setVariable("detection_start_time", tostring(os.time()))
    
    local detection_start = os.time()
    local transcription = ""
    local speech_detected = false
    
    -- Bucle de análisis durante 3 segundos
    while session:ready() do
        local elapsed_time = os.time() - detection_start
        
        if elapsed_time >= config.detection_timeout then
            log_message("INFO", "Timeout detección alcanzado (" .. config.detection_timeout .. "s)")
            break
        end
        
        -- Obtener eventos de speech
        session:sleep(100) -- 100ms entre checks
        
        -- Simular obtención de transcripción (implementar según API de Vosk)
        local speech_event = session:getVariable("detect_speech_result")
        if speech_event and speech_event ~= "" then
            transcription = transcription .. " " .. speech_event
            speech_detected = true
            log_message("DEBUG", "Speech: " .. speech_event)
        end
        
        -- Analizar transcripción acumulada cada 500ms
        if speech_detected and elapsed_time > 0.5 then
            local voicemail_probability = analyze_voicemail_patterns(transcription)
            
            if voicemail_probability >= config.confidence_threshold then
                log_message("WARNING", "=== BUZÓN DETECTADO - CORTANDO LLAMADA ===")
                log_message("INFO", "Transcripción: " .. transcription)
                log_message("INFO", "Confianza: " .. voicemail_probability .. "%")
                
                -- Establecer variables de resultado
                session:setVariable("detection_result", "voicemail")
                session:setVariable("detection_confidence", tostring(voicemail_probability))
                session:setVariable("transcription_text", transcription)
                
                -- Cortar la llamada inmediatamente con error 503
                session:execute("respond", "503 Service Unavailable - Voicemail Detected")
                session:hangup("CALL_REJECTED")
                
                log_message("INFO", "Llamada cortada por detección de buzón")
                return
            end
        end
    end
    
    -- Si llegamos aquí, no se detectó buzón
    if speech_detected then
        log_message("INFO", "=== HUMANO DETECTADO - Continuando llamada ===")
        session:setVariable("detection_result", "human")
        session:setVariable("detection_confidence", "95")
    else
        log_message("INFO", "=== SIN SPEECH DETECTADO - Asumiendo humano ===")
        session:setVariable("detection_result", "no_speech") 
        session:setVariable("detection_confidence", "50")
    end
    
    -- Detener ASR
    session:execute("detect_speech", "stop")
end

-- Función para analizar patrones de buzón de voz
local function analyze_voicemail_patterns(text)
    if not text or text == "" then
        return 0
    end
    
    local text_lower = string.lower(text)
    local voicemail_indicators = {
        "buzon", "mensaje", "tono", "beep", "pitido", 
        "no puedo atender", "deja tu mensaje", "despues del tono",
        "tras la señal", "no estoy disponible", "gracias por llamar",
        "hola has llamado", "buenas has contactado"
    }
    
    local matches = 0
    local total_indicators = #voicemail_indicators
    
    for _, indicator in ipairs(voicemail_indicators) do
        if string.find(text_lower, indicator) then
            matches = matches + 1
            log_message("DEBUG", "Patrón buzón encontrado: " .. indicator)
        end
    end
    
    -- Calcular probabilidad basada en matches
    local probability = (matches / total_indicators) * 100
    
    -- Ajustes adicionales basados en contexto
    if string.find(text_lower, "beep") or string.find(text_lower, "tono") then
        probability = probability + 20
    end
    
    if string.find(text_lower, "mensaje") and string.find(text_lower, "despues") then
        probability = probability + 15
    end
    
    return math.min(probability, 100) -- Max 100%
end

-- Ejecutar handler principal
log_message("INFO", "=== Iniciando Bridge Voicemail Detector ===")
handle_bridge_event()