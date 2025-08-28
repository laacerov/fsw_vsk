--[[
FreeSWITCH Lua Script: Post-Bridge Voicemail Detection Engine  
Se activa DESPUÉS de establecer el bridge para detección en paralelo
Análisis durante los primeros 3 segundos de conexión
]]

-- Configuración
local config = {
    classification_api_url = "http://classification-api:8080", 
    max_detection_time = 3, -- 3 segundos como especifica el usuario
    confidence_threshold_high = 85.0,
    confidence_threshold_low = 60.0,
    debug_mode = true,
    vosk_server_url = "ws://vosk-voicemail:2800"
}

-- Función de logging
local function log_message(level, message)
    if config.debug_mode or level ~= "DEBUG" then
        freeswitch.consoleLog(level, "[VOICEMAIL_DETECTOR] " .. message .. "\n")
    end
end

-- Función para hacer petición HTTP a la API
local function call_classification_api(transcription, call_data)
    local json = require "json"
    local http = require "socket.http"
    local ltn12 = require "ltn12"
    
    -- Preparar datos para la API
    local request_data = {
        call_id = call_data.uuid,
        transcription = transcription,
        caller_number = call_data.caller,
        destination_number = call_data.destination,
        call_start_time = call_data.start_time,
        audio_duration = call_data.duration
    }
    
    local json_data = json.encode(request_data)
    local response_body = {}
    
    log_message("INFO", "Enviando a API: " .. json_data)
    
    -- Realizar petición HTTP POST
    local result, status_code = http.request{
        url = config.classification_api_url .. "/classify",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = string.len(json_data)
        },
        source = ltn12.source.string(json_data),
        sink = ltn12.sink.table(response_body)
    }
    
    if not result then
        log_message("ERROR", "Error en petición HTTP: " .. tostring(status_code))
        return nil
    end
    
    -- Parsear respuesta JSON
    local response_json = table.concat(response_body)
    log_message("DEBUG", "Respuesta API: " .. response_json)
    
    local success, response_data = pcall(json.decode, response_json)
    if not success then
        log_message("ERROR", "Error parseando JSON: " .. response_json)
        return nil
    end
    
    return response_data
end

-- Función principal de detección
local function detect_voicemail()
    local session = freeswitch.Session()
    
    if not session:ready() then
        log_message("ERROR", "Sesión no está lista")
        return
    end
    
    -- Obtener información de la llamada
    local call_data = {
        uuid = session:getVariable("call_uuid"),
        caller = session:getVariable("caller_id_number"),
        destination = session:getVariable("destination_number"),
        start_time = session:getVariable("detection_start_time"),
        duration = 0
    }
    
    log_message("INFO", "Iniciando detección para Call-ID: " .. call_data.uuid)
    
    -- Variables para acumular transcripción
    local transcription = ""
    local detection_start = os.time()
    local last_speech_activity = detection_start
    
    -- Configurar callback para eventos de speech
    session:setInputCallback("speech_detection_callback")
    
    -- Bucle principal de detección
    while session:ready() do
        local current_time = os.time()
        local elapsed_time = current_time - detection_start
        
        -- Timeout de detección
        if elapsed_time > config.max_detection_time then
            log_message("WARNING", "Timeout en detección después de " .. elapsed_time .. " segundos")
            session:setVariable("detection_action", "detection_timeout")
            break
        end
        
        -- Obtener eventos de speech
        local speech_event = session:getVariable("last_detected_speech")
        if speech_event and speech_event ~= "" then
            transcription = transcription .. " " .. speech_event
            last_speech_activity = current_time
            log_message("DEBUG", "Transcripción actualizada: " .. transcription)
            
            -- Limpiar variable para próximo evento
            session:setVariable("last_detected_speech", "")
        end
        
        -- Si tenemos suficiente transcripción, analizar
        if string.len(transcription) > 50 then
            log_message("INFO", "Analizando transcripción: " .. transcription)
            
            -- Llamar a la API de clasificación
            call_data.duration = elapsed_time
            local classification_result = call_classification_api(transcription, call_data)
            
            if classification_result then
                local confidence = classification_result.confidence or 0
                local result = classification_result.result or "uncertain"
                
                log_message("INFO", "Resultado clasificación: " .. result .. " (confianza: " .. confidence .. "%)")
                
                -- Establecer variables de sesión
                session:setVariable("detection_confidence", tostring(confidence))
                session:setVariable("detection_result", result)
                session:setVariable("transcription_text", transcription)
                
                -- Determinar acción basada en confianza
                if confidence >= config.confidence_threshold_high then
                    if result == "voicemail" then
                        log_message("INFO", "BUZÓN CONFIRMADO - Cortando llamada")
                        session:setVariable("detection_action", "vm_confirmed")
                    else
                        log_message("INFO", "HUMANO CONFIRMADO - Continuando")
                        session:setVariable("detection_action", "human_confirmed")
                    end
                    break
                    
                elseif confidence >= config.confidence_threshold_low then
                    log_message("INFO", "DETECCIÓN DUDOSA - Marcando para revisión")
                    session:setVariable("detection_action", "vm_uncertain")
                    -- Continuar analizando un poco más
                    
                else
                    log_message("DEBUG", "Confianza baja - Continuando análisis")
                end
            else
                log_message("ERROR", "Error en API de clasificación")
            end
        end
        
        -- Pausa antes de siguiente iteración
        session:sleep(200) -- 200ms
    end
    
    -- Si salimos del bucle sin decisión clara
    if not session:getVariable("detection_action") then
        log_message("INFO", "No se pudo determinar tipo de llamada - Continuando como normal")
        session:setVariable("detection_action", "human_confirmed")
        session:setVariable("detection_confidence", "0")
    end
    
    log_message("INFO", "Detección completada - Acción: " .. session:getVariable("detection_action"))
end

-- Callback para eventos de speech detection
function speech_detection_callback(session, type, obj)
    if type == "dtmf" then
        return
    end
    
    if obj and obj.body then
        -- Procesar resultado de Vosk
        local speech_text = obj.body
        if speech_text and speech_text ~= "" then
            session:setVariable("last_detected_speech", speech_text)
            log_message("DEBUG", "Speech detectado: " .. speech_text)
        end
    end
end

-- Ejecutar detección principal
log_message("INFO", "=== Iniciando sistema de detección de buzones ===")
detect_voicemail()
log_message("INFO", "=== Detección finalizada ===")