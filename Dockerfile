FROM balenalib/raspberrypi3-debian-python:3.6-buster-build
ARG OpenCV_Version=4.1.2
ARG OpenVINO_Release=2019_R3.1
# enable access to the USB ports
ENV UDEV=1

# Install dependencies
RUN install_packages \
    build-essential \
    cmake \
    pkg-config \
    libjpeg-dev \
    libtiff5-dev \
    libpng-dev \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libv4l-dev \
    libxvidcore-dev \
    libx264-dev \
    libatlas-base-dev \
    gfortran && \
    cd /usr/include/linux && \
    ln -s -f ../libv4l1-videodev.h videodev.h && \
    curl -s https://bootstrap.pypa.io/get-pip.py | python3.6 && \
    python3.6 -m pip install numpy cython

# Make a libUSB that doesn't support udev to keep the NCS2 from reconnecting
RUN cd /tmp/ && \
   curl -s -L https://github.com/libusb/libusb/releases/download/v1.0.23/libusb-1.0.23.tar.bz2 | tar xjf - && \
   cd libusb-1.0.23 && \
   ./configure --disable-udev --enable-shared && \
   make -j4 && make install && \
   rm -rf /tmp/libusb-1.0.23

# Download OpenCV
RUN curl -s -L https://github.com/opencv/opencv/archive/${OpenCV_Version}.tar.gz | tar xzf - && \
    mv /opencv-${OpenCV_Version} /opencv && \
    curl -s -L https://github.com/opencv/opencv_contrib/archive/${OpenCV_Version}.tar.gz | tar xzf - && \
    mv /opencv_contrib-${OpenCV_Version} /opencv_contrib && \
# Build OpenCV
    mkdir -p /opencv-build && cd /opencv-build && \
    cmake -D CMAKE_BUILD_TYPE=RELEASE \
        -D CMAKE_INSTALL_PREFIX=/usr/local \
        -D OPENCV_EXTRA_MODULES_PATH=/opencv_contrib/modules \
        -D ENABLE_NEON=ON \
        -D BUILD_TESTS=OFF \
        -D INSTALL_PYTHON_EXAMPLES=OFF \
        -D OPENCV_ENABLE_NONFREE=ON \
        -D CMAKE_SHARED_LINKER_FLAGS=-latomic \
        -D BUILD_EXAMPLES=OFF \
        -DPYTHON3_EXECUTABLE=/usr/local/bin/python3.6 \
        –DPYTHON_INCLUDE_DIR=/usr/local/include/python3.6m \
        –DPYTHON_LIBRARY=/usr/local/lib/libpython3.6m.so \
        /opencv && \
    make --jobs=$(nproc --all) && \
    make install && \
    cd / ; rm -rf /opencv-build /opencv /opencv-contrib

ENV OpenCV_DIR=/usr/local/lib/cmake/opencv4

# Download OpenVINO
RUN git clone https://github.com/opencv/dldt.git && \
    cd /dldt/inference-engine/ && \
    git checkout ${OpenVINO_Release} && \
    git submodule init && \
    git submodule update --recursive && \
# Build OpenVINO
    mkdir -p /inference-engine-build && cd /inference-engine-build && \
# Remove the last line from this one file so we can compile... 
    sed -i "$(($(wc -l < /dldt/inference-engine/ie_bridges/python/CMakeLists.txt))),\$d" \
        /dldt/inference-engine/ie_bridges/python/CMakeLists.txt && \
    cmake -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_MKL_DNN=OFF \
        -DENABLE_CLDNN=OFF \
        -DENABLE_GNA=OFF \
        -DENABLE_SSE42=OFF \
	-DENABLE_MYRIAD=ON \
	-DTHREADING=SEQ \
	-DENABLE_PYTHON=ON \
	-DPYTHON_EXECUTABLE=/usr/local/bin/python3.6 \
	-DPYTHON_LIBRARY=/usr/local/lib/libpython3.6m.so \
	-DPYTHON_INCLUDE_DIR=/usr/local/include/python3.6m \
        /dldt/inference-engine && \
    make --jobs=$(nproc --all) && \
    cd / && rm -rf /inference-engine-build && \
    cp /dldt/inference-engine/thirdparty/movidius/mvnc/src/97-myriad-usbboot.rules /etc/udev/rules.d

ENV IE_PLUGINS_PATH=/dldt/inference-engine/bin/armv7l/Release/lib
ENV LD_LIBRARY_PATH=${IE_PLUGINS_PATH}:${LD_LIBRARY_PATH}
ENV PATH=${PATH}:/dldt/inference-engine/bin/armv7l/Release
ENTRYPOINT ["python3"]
