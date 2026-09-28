FROM debian:bookworm-slim

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

# Architecture-independent path to the OpenMPI headers (Debian keeps them in
# /usr/lib/<arch>-linux-gnu/openmpi/include, e.g. x86_64 or aarch64)
RUN ln -s "/usr/lib/$(uname -m)-linux-gnu/openmpi/include" /usr/local/include/openmpi && \
    test -f /usr/local/include/openmpi/mpi.h

# Create a non-root user
RUN useradd -ms /bin/bash mitgcm
USER mitgcm
ENV USER_HOME_DIR=/home/mitgcm
WORKDIR /home/mitgcm

# MITgcm will be mounted at runtime at /mitgcm
# This allows users to modify source code without rebuilding the Docker image
ENV MITGCM_ROOT=/mitgcm
ENV MITGCM_ROOTDIR=/mitgcm
WORKDIR /mitgcm/verification

# Set environment variables for NetCDF and MPI (installed via apt)
ENV NETCDF_ROOT=/usr
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/mitgcm/tools
ENV MPI_INC_DIR=/usr/local/include/openmpi
ENV MPIINCLUDEDIR=/usr/local/include/openmpi

# Detect architecture and set appropriate optfile
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        echo "export OPTFILE=/mitgcm/tools/build_options/linux_amd64_gfortran" > /home/mitgcm/.optfile_env; \
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        echo "export OPTFILE=/mitgcm/tools/build_options/linux_arm64_gfortran" > /home/mitgcm/.optfile_env; \
    else \
        echo "export OPTFILE=/mitgcm/tools/build_options/linux_amd64_gfortran" > /home/mitgcm/.optfile_env; \
    fi && \
    cat /home/mitgcm/.optfile_env >> /home/mitgcm/.bashrc

# Default command: interactive bash shell
# Users specify experiment when running experiment_compile.sh or experiment_run_no_compile.sh
CMD ["/bin/bash"]
