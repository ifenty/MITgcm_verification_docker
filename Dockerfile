FROM debian:bookworm-slim

# Build arguments for optfile and MPI architecture (defaults: ARM64 for backward compatibility)
ARG OPTFILE=linux_arm64_gfortran
ARG MPI_ARCH=aarch64-linux-gnu

# Use bash as the default shell
SHELL ["/bin/bash", "-c"]

USER root

# Install required packages including MPI
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    gfortran \
    gcc \
    g++ \
    make \
    perl \
    csh \
    tcsh \
    vim \
    less \
    git \
    wget \
    ca-certificates \
    libnetcdf-dev \
    libnetcdff-dev \
    netcdf-bin \
    libopenmpi-dev \
    openmpi-bin \
    libnetcdf-mpi-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd -ms /bin/bash mitgcm
USER mitgcm
ENV USER_HOME_DIR=/home/mitgcm
WORKDIR /home/mitgcm

# Copy the entire MITgcm directory into the container
# This includes all source code and build options in tools/build_options/
COPY --chown=mitgcm:mitgcm . /home/mitgcm/MITgcm

WORKDIR /home/mitgcm/MITgcm/verification

# Set environment variables for NetCDF and MPI (installed via apt)
ENV NETCDF_ROOT=/usr
ENV PATH=/home/mitgcm/MITgcm/tools:$PATH
ENV OPTFILE=/home/mitgcm/MITgcm/tools/build_options/${OPTFILE}
ENV MPI_INC_DIR=/usr/lib/${MPI_ARCH}/openmpi/include
ENV MPIINCLUDEDIR=/usr/lib/${MPI_ARCH}/openmpi/include

# Default command: interactive bash shell
# Users specify experiment when running docker_compile_only.sh or run_no_compile.sh
CMD ["/bin/bash"]
