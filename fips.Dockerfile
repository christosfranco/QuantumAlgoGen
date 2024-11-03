# Use Ubuntu 22.04 as the base image
FROM ubuntu:22.04

# Set environment variables
ENV WORKSPACE=/root/quantumsafe
ENV BUILD_DIR=$WORKSPACE/build

# Install required packages
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    perl \
    cmake \
    autoconf \
    libtool \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Create the build directory and symlink
RUN mkdir -p $BUILD_DIR/lib64 && ln -s $BUILD_DIR/lib64 $BUILD_DIR/lib

# Clone and build OpenSSL with FIPS support
WORKDIR $WORKSPACE
RUN git clone https://github.com/openssl/openssl.git \
    && cd openssl \
    && ./Configure \
        --prefix=$BUILD_DIR \
        enable-fips \
        no-ssl no-tls1 no-tls1_1 no-afalgeng \
        no-shared threads -lm \
    && make -j$(nproc) \
    && make -j$(nproc) install_sw install_ssldirs

# Build the OpenSSL FIPS module
RUN cd openssl \
    && ./Configure fips \
    && make -j$(nproc) \
    && make -j$(nproc) install_fips

# Clone and build liboqs
WORKDIR $WORKSPACE
RUN git clone https://github.com/open-quantum-safe/liboqs.git \
    && cd liboqs \
    && mkdir build && cd build \
    && cmake \
        -DCMAKE_INSTALL_PREFIX=$BUILD_DIR \
        -DBUILD_SHARED_LIBS=ON \
        -DOQS_USE_OPENSSL=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DOQS_BUILD_ONLY_LIB=ON \
        -DOQS_DIST_BUILD=ON \
        .. \
    && make -j$(nproc) \
    && make -j$(nproc) install

# Clone and build oqs-provider
WORKDIR $WORKSPACE
RUN git clone https://github.com/open-quantum-safe/oqs-provider.git \
    && cd oqs-provider \
    && liboqs_DIR=$BUILD_DIR cmake \
        -DCMAKE_INSTALL_PREFIX=$WORKSPACE/oqs-provider \
        -DOPENSSL_ROOT_DIR=$BUILD_DIR \
        -DCMAKE_BUILD_TYPE=Release \
        -S . \
        -B _build \
    && cmake --build _build

# Manually copy the built libraries
RUN cp $WORKSPACE/oqs-provider/_build/lib/* $BUILD_DIR/lib/

# Update OpenSSL config to include oqsprovider and enable FIPS
RUN sed -i "s/default = default_sect/default = default_sect\noqsprovider = oqsprovider_sect/g" $BUILD_DIR/ssl/openssl.cnf \
    && sed -i "s/\[default_sect\]/\[default_sect\]\nactivate = 1\n\[oqsprovider_sect\]\nactivate = 1\nfips = fips_sect\n/g" $BUILD_DIR/ssl/openssl.cnf \
    && echo -e "[fips_sect]\nactivate = 1" >> $BUILD_DIR/ssl/openssl.cnf

# Set the environment variables for OpenSSL to use oqsprovider and FIPS
ENV OPENSSL_CONF=$BUILD_DIR/ssl/openssl.cnf
ENV OPENSSL_MODULES=$BUILD_DIR/lib

# Verify that oqsprovider and FIPS are available in OpenSSL
RUN $BUILD_DIR/bin/openssl list -providers -verbose -provider oqsprovider

# Ensure the container starts with bash for interactive usage
CMD ["/bin/bash"]

# openssl req -x509 -new -newkey dilithium3 -keyout dilithium3_CA.key -out dilithium_CA.crt -nodes -subj "/CN=test CA" -days 365

# openssl x509 -in dilithium_CA.crt  -text
