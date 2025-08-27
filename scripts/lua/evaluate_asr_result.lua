--[[
Script para evaluar resultados de ASR y detectar patrones de buzón
]]

-- Obtener sesión
local session = freeswitch.Session()

if not session:ready() then
    freeswitch.consoleLog("ERROR", "Sesión no está lista\n")
    return
end

-- Obtener variables de la sesión
local call_uuid = session:getVariable("call_uuid") or session:getVariable("uuid")
local detection_result = session:getVariable("detection_result") or ""
local speech_text = session:getVariable("detect_speech_result") or ""

freeswitch.consoleLog("INFO", "=== EVALUACIÓN ASR ===\n")
freeswitch.consoleLog("INFO", "Call-ID: " .. call_uuid .. "\n")
freeswitch.consoleLog("INFO", "Speech Text: " .. speech_text .. "\n")

-- Patrones comunes de buzones de voz en español
local voicemail_patterns = {
    "hola.*llamado", "gracias.*llamar", "buzón.*voz", "buzon.*voz",
    "deja.*mensaje", "después.*tono", "no.*puedo.*atender",
    "mensaje.*después", "ausente", "ocupado", "leave.*message",
    "thank.*you.*call", "not.*available", "voicemail", "contestador"
}

-- Convertir a minúsculas para comparación
local speech_lower = string.lower(speech_text)
local pattern_matches = 0
local matched_patterns = {}

-- Buscar patrones de buzón
for _, pattern in ipairs(voicemail_patterns) do
    if string.match(speech_lower, pattern) then
        pattern_matches = pattern_matches + 1
        table.insert(matched_patterns, pattern)
        freeswitch.consoleLog("INFO", "Patrón de buzón encontrado: " .. pattern .. "\n")
    end
end

-- Calcular confianza basada en patrones encontrados
local confidence = 0
if pattern_matches > 0 then
    confidence = math.min(95, (pattern_matches * 30) + 15)
end

-- Determinar resultado
local result = "unknown"
if confidence >= 70 then
    result = "voicemail_detected"
elseif confidence >= 30 then
    result = "possible_voicemail"
else
    result = "human_or_unknown"
end

-- Establecer variables de resultado
session:setVariable("asr_confidence", tostring(confidence))
session:setVariable("asr_result", result)
session:setVariable("matched_patterns", table.concat(matched_patterns, ","))
session:setVariable("pattern_count", tostring(pattern_matches))

-- Log de resultado final
freeswitch.consoleLog("INFO", "=== RESULTADO FINAL ===\n")
freeswitch.consoleLog("INFO", "Patrones encontrados: " .. pattern_matches .. "\n")
freeswitch.consoleLog("INFO", "Confianza: " .. confidence .. "%\n")
freeswitch.consoleLog("INFO", "Resultado: " .. result .. "\n")

if confidence >= 70 then
    freeswitch.consoleLog("WARNING", "🎯 BUZÓN DETECTADO con " .. confidence .. "% de confianza\n")
    session:execute("playback", "tone_stream://%(500,500,300,400)")
else
    freeswitch.consoleLog("INFO", "💬 Posible conversación humana o resultado incierto\n")
    session:execute("playback", "tone_stream://%(200,200,600,700)")
end