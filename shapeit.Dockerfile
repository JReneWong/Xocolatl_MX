FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config \
        wget curl ca-certificates git tar bzip2 \
        zlib1g-dev libbz2-dev liblzma-dev libcurl4-openssl-dev libssl-dev libdeflate-dev \
    && rm -rf /var/lib/apt/lists/*

ENV LC_ALL=C
ENV HTSLIB_VERSION=1.16
ENV BOOST_VERSION=1.73.0
ENV BOOST_VERSION_U=1_73_0

RUN mkdir -p /opt/src

# HTSlib
WORKDIR /opt/src
RUN wget -q "https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2" \
    && tar -xf "htslib-${HTSLIB_VERSION}.tar.bz2" \
    && mv "htslib-${HTSLIB_VERSION}" htslib \
    && cd htslib && make

# Boost
WORKDIR /opt/src
RUN wget -q "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION_U}.tar.bz2" \
    && tar --bzip2 -xf "boost_${BOOST_VERSION_U}.tar.bz2" \
    && cd "boost_${BOOST_VERSION_U}" \
    && ./bootstrap.sh --with-libraries=iostreams,program_options,serialization --prefix=../boost \
    && ./b2 install

# Shapeit5
WORKDIR /opt/src
RUN git clone --depth 1 --recurse-submodules https://github.com/odelaneau/shapeit.git
WORKDIR /opt/src/shapeit/phase_common
RUN make HTSSRC=/opt/src/htslib \
        HTSLIB_INC=/opt/src/htslib \
        HTSLIB_LIB=/opt/src/htslib/libhts.a \
        BOOST_INC=/opt/src/boost/include \
        BOOST_LIB_IO=/opt/src/boost/lib/libboost_iostreams.a \
        BOOST_LIB_PO=/opt/src/boost/lib/libboost_program_options.a \
        BOOST_LIB_SE=/opt/src/boost/lib/libboost_serialization.a

# runtime
FROM ubuntu:22.04

ENV LC_ALL=C DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        zlib1g libbz2-1.0 liblzma5 libcurl4 libssl3 libdeflate0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/src/shapeit/phase_common/bin/* /usr/local/bin/

ENTRYPOINT ["phase_common"]