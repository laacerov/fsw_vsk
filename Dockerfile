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
    sngrep git wget curl ca-certificates libltdl-dev  libtool && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Compila e instala libks
RUN git clone -c http.sslverify=false https://github.com/signalwire/libks.git /usr/local/src/libks && \
    cd /usr/local/src/libks && \
    cmake . && \
    make && make install

# Compila e instala signalwire-c
RUN git clone -c http.sslverify=false https://github.com/signalwire/signalwire-c.git /usr/local/src/signalwire-c && \
    cd /usr/local/src/signalwire-c && \
    cmake . && \
    make && make install

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
    make && make install

# Compila e instala spandsp
RUN git clone -c http.sslverify=false https://github.com/freeswitch/spandsp.git /usr/local/src/spandsp && \
    cd /usr/local/src/spandsp && \
    ./bootstrap.sh && \
    ./configure && \
    make && make install

# Revion de version libtools
RUN apt-get update && apt-get install -y libtool
RUN find / -name libtool
RUN ln -s /usr/local/src/sofia-sip/libtool /usr/bin/libtool
RUN libtool --version  

# Descarga, compila e instala FreeSWITCH
RUN cd /usr/local/src && \
    git clone -c http.sslverify=false https://github.com/alphacep/freeswitch.git && \
    cd freeswitch && \
    ./bootstrap.sh

# Copia el archivo de módulos personalizado
COPY modules.conf /usr/local/src/freeswitch/modules.conf
RUN cd /usr/local/src/freeswitch/ &&\
    ./configure && \
    make && \
    make install && \
    make cd-sounds-install && \
    make cd-moh-install && \
    make samples

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
CMD ["/usr/local/freeswitch/bin/freeswitch", "-nonat"]
 