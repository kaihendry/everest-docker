# syntax=docker/dockerfile:1
FROM debian:11 AS builder

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    git \
    rsync \
    wget \
    cmake \
    doxygen \
    graphviz \
    build-essential \
    clang-format \
    clang-tidy \
    cppcheck \
    libboost-all-dev \
    maven \
    openjdk-11-jdk \
    nodejs \
    npm \
    libsqlite3-dev \
    python3-pip \
    libssl-dev \
    libcurl4-openssl-dev \
    libpcap-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/everest

RUN mkdir -p /workspace/everest/cpm_source_cache
ENV CPM_SOURCE_CACHE="/workspace/everest/cpm_source_cache"

RUN git clone https://github.com/EVerest/everest-cmake.git
RUN git clone https://github.com/EVerest/everest-utils.git
WORKDIR /workspace/everest/everest-utils/ev-dev-tools
RUN python3 -m pip install .
WORKDIR /workspace/everest
RUN git clone https://github.com/EVerest/everest-dev-environment.git
WORKDIR /workspace/everest/everest-dev-environment/dependency_manager
RUN python3 -m pip install .
WORKDIR /workspace/everest
RUN git clone https://github.com/EVerest/ext-switchev-iso15118.git

WORKDIR /workspace/everest

RUN rm -rf "/workspace/everest/everest-core"
RUN git clone https://github.com/EVerest/everest-core.git

RUN --mount=type=cache,target=/workspace/everest/everest-core/build \
    --mount=type=cache,target=/workspace/everest/cpm_source_cache \
    mkdir -p "/workspace/everest/everest-core/build" && \
    cd "/workspace/everest/everest-core/build" && \
    cmake .. -DEVEREST_BUILD_ALL_MODULES=ON -DCMAKE_INSTALL_PREFIX=/opt/everest && \
    make -j"$(nproc)" install

RUN mkdir -p /opt/everest/config/user-config
COPY logging.ini /opt/everest/config

# syntax=docker/dockerfile:1
FROM debian:11 AS admin-builder

WORKDIR /workspace/everest

RUN apt-get update \
    && apt-get install --no-install-recommends -y curl ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    git \
    openssh-client \
    nodejs

RUN git clone https://github.com/EVerest/everest-admin-panel.git \
    && cd /workspace/everest/everest-admin-panel \
    && npm install \
    && npm run build

# syntax=docker/dockerfile:1
FROM debian:11-slim
ARG TARGETARCH

RUN apt-get update \
    && apt-get install --no-install-recommends -y curl ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    openjdk-11-jre \
    nodejs \
    python3-pip \
    sqlite3 \
    libboost-program-options1.74.0 \
    libboost-log1.74.0 \
    libboost-chrono1.74.0 \
    libboost-system1.74.0 \
    libevent-2.1-7 \
    libevent-pthreads-2.1-7 \
    libssl1.1 \
    libcurl4 \
    less \
    patch

RUN if [ "$TARGETARCH" = "arm64" ]; then \
        apt-get install --no-install-recommends -y gcc python3-dev ; \
        fi;

RUN apt-get clean \
        && rm -rf /var/lib/apt/lists/*

COPY --from=builder /workspace/everest/ext-switchev-iso15118/requirements.txt ./
RUN pip install --user -r requirements.txt

WORKDIR /opt/everest
COPY --from=builder /opt/everest ./

COPY --from=admin-builder /workspace/everest/everest-admin-panel/dist admin/

RUN npm install -g serve

RUN pip install supervisor
COPY supervisord.conf ./

CMD [ "supervisord" ]
