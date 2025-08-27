# Usa Ubuntu 20.04 como base
FROM ubuntu:20.04

# Establece la variable de entorno para evitar prompts interactivos
ENV DEBIAN_FRONTEND=noninteractive

# Actualiza el sistema e instala las dependencias
RUN sed -i 's|http://.*.ubuntu.com|http://archive.ubuntu.com|g' /etc/apt/sources.list && \
    apt-get update && apt-get install --no-install-recommends -y \
    build-essential pkg-config uuid-dev zlib1g-dev libjpeg-dev libsqlite3-dev \
    libcurl4-openssl-dev libpcre3-dev libspeexdsp-dev libldns-dev libedit-dev \
    libtiff5-dev yasm libopus-dev libsndfile1-dev unzip libavformat-dev \
    libswscale-dev libavresample-dev liblua5.2-dev liblua5.2-0 cmake libpq-dev \
    unixodbc-dev autoconf automake ntpdate libxml2-dev libpq-dev libpq5 sngrep \
    sngrep git wget curl ca-certificates libltdl-dev libtool \
    libssl-dev libncurses5-dev libjson-c-dev libsystemd-dev \
    libwebsockets-dev libjansson-dev libpcre2-dev libpcre3-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar libtpl manualmente
RUN cd /usr/local/src && \
    wget -O libtpl-1.6.1.tar.gz https://github.com/troydhanson/tpl/archive/v1.6.1.tar.gz && \
    tar -xzf libtpl-1.6.1.tar.gz && \
    cd tpl-1.6.1 && \
    gcc -fPIC -shared -o libtpl.so src/tpl.c && \
    cp src/tpl.h /usr/local/include/ && \
    cp libtpl.so /usr/local/lib/ && \
    echo "/usr/local/lib" > /etc/ld.so.conf.d/libtpl.conf && \
    ldconfig

# Compila e instala libks con branch vosk-fix (requerido para mod_vosk)
RUN git clone --branch vosk-fix --single-branch -c http.sslverify=false https://github.com/alphacep/libks.git /usr/local/src/libks && \
    cd /usr/local/src/libks && \
    cmake . && \
    make && make install && \
    ldconfig && \
    echo "=== Verificando libks instalado ===" && \
    find /usr/local -name "*libks*" && \
    find /usr/local -name "*.pc" | grep -i ks

# Saltamos signalwire-c por incompatibilidad con libks vosk-fix
# FreeSWITCH puede funcionar sin signalwire-c para mod_vosk básico

    # Compila e instala sofia-sip
RUN git clone -c http.sslverify=false https://github.com/freeswitch/sofia-sip.git /usr/local/src/sofia-sip
COPY Makefile /usr/local/src/sofia-sip/Makefile   
RUN chmod +r /usr/local/src/sofia-sip/Makefile
RUN cd /usr/local/src/sofia-sip && \
    libtoolize && \
    aclocal && \
    autoheader && \
    autoconf && \
    automake --add-missing && \
    ./configure && \
    make && make install && \
    ldconfig

# Compila e instala spandsp
RUN git clone -c http.sslverify=false https://github.com/freeswitch/spandsp.git /usr/local/src/spandsp && \
    cd /usr/local/src/spandsp && \
    ./bootstrap.sh && \
    ./configure && \
    make && make install && \
    ldconfig

# Revion de version libtools
RUN apt-get update && apt-get install -y libtool
RUN find / -name libtool
RUN ln -s /usr/local/src/sofia-sip/libtool /usr/bin/libtool
RUN libtool --version  

# Descarga FreeSWITCH con mod_vosk integrado de alphacep
RUN cd /usr/local/src && \
    git clone -c http.sslverify=false https://github.com/alphacep/freeswitch.git && \
    cd freeswitch && \
    ./bootstrap.sh

# Copia el archivo de módulos personalizado
COPY modules.conf /usr/local/src/freeswitch/modules.conf

# Configurar y compilar FreeSWITCH con verificación de errores
RUN cd /usr/local/src/freeswitch/ && \
    ./configure --enable-core-pgsql-support \
                --enable-core-odbc-support && \
    echo "=== Configuración completada ===" && \
    make -j$(nproc) && \
    echo "=== Compilación completada ===" && \
    make install && \
    echo "=== Instalación completada ===" && \
    ldconfig && \
    echo "=== ldconfig ejecutado ===" && \
    ls -la /usr/local/freeswitch/mod/ && \
    echo "=== Verificando módulos instalados ==="

# Instalar sonidos y samples por separado
RUN cd /usr/local/src/freeswitch/ && \
    make cd-sounds-install && \
    make cd-moh-install && \
    make samples

# mod_vosk ya está integrado en el repositorio de alphacep

# Verificar instalación de módulos
RUN echo "=== Verificando módulos instalados ===" && \
    ls -la /usr/local/freeswitch/mod/ | head -20 && \
    echo "=== Fin de verificación ==="

# Configuración del servicio systemd para FreeSWITCH
COPY freeswitch.service /etc/systemd/system/freeswitch.service

# Configuracion adicional
RUN ln -s /usr/local/freeswitch/conf /etc/freeswitch 
RUN ln -s /usr/local/freeswitch/bin/fs_cli /usr/bin/fs_cli 
RUN ln -s /usr/local/freeswitch/bin/freeswitch /usr/sbin/freeswitch

# Expone los puertos necesarios
EXPOSE 5060-5061/udp
EXPOSE 5060-5061/tcp
EXPOSE 8021/tcp

# Comando de inicio
CMD ["/usr/local/freeswitch/bin/freeswitch", "-nc", "-nf"]
 