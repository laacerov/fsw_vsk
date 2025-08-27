--[[
FreeSWITCH Lua Script: Outbound Bridge with Voicemail Detection
Ejecuta bridge saliente mientras detecta buzones en paralelo
]]

-- Configuración
local config = {
    gateway_name = "voicemail_detection_gw",
    detection_timeout = 30,
    bridge_timeout = 60,
    enable_recording = true,
    debug_mode = true
}

local function log_message(level, message)
    if config.debug_mode or level ~= "DEBUG" then
        freeswitch.consoleLog(level, "[OUTBOUND_BRIDGE_DETECTOR] " .. message .. "\n")
    end
end

local function outbound_bridge_with_detection()
    local session = freeswitch.Session()
    
    if not session:ready() then
        log_message("ERROR", "Sesión no está lista para bridge saliente")
        return
    end
    
    -- Obtener variables de la llamada
    local auth_prefix = session:getVariable("auth_prefix") or "77751"
    local destination_clean = session:getVariable("destination_clean") or ""
    local full_destination = session:getVariable("full_destination") or ""
    local call_uuid = session:getVariable("call_uuid")
    local caller_number = session:getVariable("caller_id_number")
    
    log_message("INFO", "=== INICIANDO BRIDGE SALIENTE CON DETECCIÓN ===")
    log_message("INFO", "Call-ID: " .. call_uuid)
    log_message("INFO", "Origen: " .. caller_number)
    log_message("INFO", "Destino: " .. full_destination)
    log_message("INFO", "Gateway: " .. config.gateway_name)
    
    -- Construir string de destino para el bridge
    local bridge_string = "sofia/gateway/" .. config.gateway_name .. "/" .. full_destination
    
    -- Configurar variables de bridge
    session:setVariable("bridge_timeout", tostring(config.bridge_timeout))
    session:setVariable("originate_timeout", tostring(config.bridge_timeout))
    session:setVariable("call_timeout", tostring(config.bridge_timeout))
    
    -- Inicializar grabación si está habilitada
    local record_file = ""
    if config.enable_recording then
        record_file = "/tmp/outbound_" .. call_uuid .. ".wav"
        session:setVariable("record_file", record_file)
        session:execute("record_session", record_file)
        log_message("DEBUG", "Iniciando grabación: " .. record_file)
    end
    
    -- Configurar detección ASR antes del bridge
    log_message("INFO", "Configurando detección ASR para bridge saliente")
    session:execute("detect_speech", "vosk default default")
    
    -- Variables para tracking de detección
    local detection_active = true
    local detection_result = "unknown"
    local detection_confidence = 0
    local bridge_start_time = os.time()
    local last_speech_event = ""
    local accumulated_transcription = ""
    
    -- Configurar callback para eventos de speech durante bridge
    session:setInputCallback("outbound_speech_callback")
    
    log_message("INFO", "Ejecutando bridge a: " .. bridge_string)
    
    -- Ejecutar el bridge con detección paralela
    session:execute("bridge", bridge_string)
    
    -- Obtener resultado del bridge
    local hangup_cause = session:hangupCause()
    local bridge_duration = os.time() - bridge_start_time
    
    log_message("INFO", "Bridge terminado - Causa: " .. hangup_cause .. ", Duración: " .. bridge_duration .. "s")
    
    -- Detener detección ASR
    session:execute("detect_speech", "stop")
    
    -- Detener grabación
    if config.enable_recording and record_file ~= "" then
        session:execute("stop_record_session")
        log_message("DEBUG", "Grabación detenida: " .. record_file)
    end
    
    -- Obtener transcripción final
    accumulated_transcription = session:getVariable("accumulated_speech") or ""
    
    -- Analizar resultado del bridge
    if hangup_cause == "NORMAL_CLEARING" then
        -- Llamada exitosa - verificar si hubo detección durante la llamada
        if bridge_duration < 15 and accumulated_transcription ~= "" then
            log_message("WARNING", "Llamada corta con transcripción - Posible buzón")
            
            -- Analizar transcripción para patrones de buzón
            local voicemail_patterns = {
                "hola.*llamado", "gracias.*llamar", "buzón.*voz", 
                "deja.*mensaje", "después.*tono", "no.*puedo.*atender"
            }
            
            local pattern_matches = 0
            local transcription_lower = string.lower(accumulated_transcription)
            
            for _, pattern in ipairs(voicemail_patterns) do
                if string.match(transcription_lower, pattern) then
                    pattern_matches = pattern_matches + 1
                    log_message("DEBUG", "Patrón encontrado: " .. pattern)
                end
            end
            
            -- Calcular confianza basada en patrones encontrados
            detection_confidence = math.min(95, (pattern_matches * 25) + 20)
            
            if detection_confidence >= 75 then
                detection_result = "voicemail"
                session:setVariable("bridge_result_action", "vm_detected_outbound")
                log_message("WARNING", "BUZÓN DETECTADO - Confianza: " .. detection_confidence .. "%")
            else
                detection_result = "human"
                session:setVariable("bridge_result_action", "call_successful")
                log_message("INFO", "Llamada normal completada")
            end
        else
            -- Llamada larga normal
            detection_result = "human"
            session:setVariable("bridge_result_action", "call_successful")
            log_message("INFO", "Llamada larga completada - Humano detectado")
        end
        
    elseif hangup_cause == "NO_ANSWER" or hangup_cause == "USER_BUSY" then
        -- No contesta o ocupado
        detection_result = "no_answer"
        session:setVariable("bridge_result_action", "call_failed")
        log_message("INFO", "Llamada no contestada: " .. hangup_cause)
        
    else
        -- Otros errores
        detection_result = "failed"
        session:setVariable("bridge_result_action", "call_failed")
        log_message("WARNING", "Llamada falló: " .. hangup_cause)
    end
    
    -- Establecer variables de resultado
    session:setVariable("detection_result", detection_result)
    session:setVariable("detection_confidence", tostring(detection_confidence))
    session:setVariable("transcription_text", accumulated_transcription)
    session:setVariable("bridge_duration", tostring(bridge_duration))
    session:setVariable("original_hangup_cause", hangup_cause)
    
    log_message("INFO", "=== RESULTADO FINAL ===")
    log_message("INFO", "Detección: " .. detection_result)
    log_message("INFO", "Confianza: " .. detection_confidence .. "%")
    log_message("INFO", "Transcripción: " .. accumulated_transcription)
    log_message("INFO", "Acción: " .. (session:getVariable("bridge_result_action") or "unknown"))
    
    -- Transferir al dialplan para procesar resultado
    session:transfer("process_bridge_result", "XML", "default")
end

-- Callback para eventos de speech durante bridge
function outbound_speech_callback(session, type, obj)
    if type == "dtmf" then
        return
    end
    
    if obj and obj.body then
        local speech_text = obj.body
        if speech_text and speech_text ~= "" then
            local current_speech = session:getVariable("accumulated_speech") or ""
            session:setVariable("accumulated_speech", current_speech .. " " .. speech_text)
            log_message("DEBUG", "Speech durante bridge: " .. speech_text)
        end
    end
end

-- Ejecutar función principal
log_message("INFO", "=== INICIANDO BRIDGE SALIENTE CON DETECCIÓN ===")
outbound_bridge_with_detection()