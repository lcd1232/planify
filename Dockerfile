FROM fedora:42 AS builder

RUN dnf install -y \
    meson \
    ninja-build \
    vala \
    gcc \
    gcc-c++ \
    cmake \
    git \
    glib2-devel \
    gtk4-devel \
    libadwaita-devel \
    libsoup3-devel \
    sqlite-devel \
    json-glib-devel \
    libgee-devel \
    libsecret-devel \
    gtksourceview5-devel \
    gettext-devel \
    desktop-file-utils \
    appstream \
    libxml2-devel \
    gobject-introspection-devel \
    libicu-devel \
    vala-devel \
    valadoc \
    && dnf clean all

# Build libical with GObject Introspection and Vala bindings
RUN git clone --branch v3.0.20 --depth 1 https://github.com/libical/libical.git /tmp/libical && \
    cmake -S /tmp/libical -B /tmp/libical/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=/usr/lib64 \
        -DBUILD_SHARED_LIBS=ON \
        -DGOBJECT_INTROSPECTION=true \
        -DICAL_GLIB_VAPI=true \
        -DICAL_GLIB=true \
        -DICAL_BUILD_DOCS=false \
        -DWITH_CXX_BINDINGS=false && \
    cmake --build /tmp/libical/build && \
    cmake --install /tmp/libical/build && \
    rm -rf /tmp/libical

# Build gxml from source
RUN git clone --branch 0.20.4 --depth 1 https://gitlab.gnome.org/GNOME/gxml.git /tmp/gxml && \
    meson setup /tmp/gxml/build /tmp/gxml --prefix=/usr --libdir=lib64 && \
    meson compile -C /tmp/gxml/build && \
    meson install -C /tmp/gxml/build && \
    rm -rf /tmp/gxml

WORKDIR /app
COPY . .

RUN meson setup build -Dwebkit=false -Dportal=false -Devolution=false --buildtype=release && meson compile -C build
