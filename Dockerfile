# PostgreSQL GIS stack
#
# This image includes the following tools
# - PostgreSQL 9.4
# - PostGIS 2.1.5 with raster, topology and sfcgal support
# - PgRouting
# - PDAL master
# - PostgreSQL PointCloud
#
# Version 1.6

FROM phusion/baseimage
MAINTAINER Vincent Picavet, vincent.picavet@oslandia.com

# Set correct environment variables.
ENV HOME /root

# Set software versions
ENV PG_VERSION 9.4
ENV PGIS_VERSION 2.1.5

# Regenerate SSH host keys. baseimage-docker does not contain any, so you
# have to do that yourself. You may also comment out this instruction; the
# init system will auto-generate one during boot.
RUN /etc/my_init.d/00_regen_ssh_host_keys.sh

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]


RUN apt-get update && apt-get install -y wget ca-certificates

# Use APT postgresql repositories for required version
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ wheezy-pgdg main ${PG_VERSION}" > /etc/apt/sources.list.d/pgdg.list && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

# packages needed for compilation
RUN apt-get update

RUN apt-get install -y autoconf build-essential cmake docbook-mathml docbook-xsl libboost-dev libboost-filesystem-dev libboost-system-dev libboost-iostreams-dev libboost-program-options-dev libboost-timer-dev libcgal-dev libcunit1-dev libgdal-dev libgeos++-dev libgeotiff-dev libgmp-dev libjson0-dev libjson-c-dev liblas-dev libmpfr-dev libopenscenegraph-dev libpq-dev libproj-dev libxml2-dev postgresql-server-dev-9.4 xsltproc git build-essential wget 

# application packages
RUN apt-get install -y postgresql-${PG_VERSION}

# download and compile SFCGAL
RUN git clone https://github.com/Oslandia/SFCGAL.git
RUN cd SFCGAL && cmake . && make -j3 && make install
# cleanup
RUN rm -Rf SFCGAL

# Download and compile PostGIS
RUN wget http://download.osgeo.org/postgis/source/postgis-${PGIS_VERSION}.tar.gz
RUN tar -xzf postgis-${PGIS_VERSION}.tar.gz
RUN cd postgis-${PGIS_VERSION} && ./configure --with-sfcgal=/usr/local/bin/sfcgal-config
RUN cd postgis-${PGIS_VERSION} && make -j3 && make install
# cleanup
RUN rm -Rf postgis-${PGIS_VERSION}.tar.gz postgis-${PGIS_VERSION}

# Download and compile pgrouting
RUN git clone https://github.com/pgRouting/pgrouting.git &&\
    cd pgrouting &&\
    mkdir build && cd build &&\
    cmake -DWITH_DOC=OFF -DWITH_DD=ON .. &&\
    make -j3 && make install
# cleanup
RUN rm -Rf pgrouting

# Compile PDAL
RUN git clone https://github.com/PDAL/PDAL.git pdal
RUN mkdir PDAL-build && \
    cd PDAL-build && \
    cmake ../pdal && \
    make -j3 && \
    make install
# cleanup
RUN rm -Rf pdal && rm -Rf PDAL-build

# Compile PointCloud
RUN git clone https://github.com/pramsey/pointcloud.git
RUN cd pointcloud && ./autogen.sh && ./configure && make -j3 && make install
# cleanup
RUN rm -Rf pointcloud

# get compiled libraries recognized
RUN ldconfig

# clean packages

# all -dev packages
RUN apt-get remove -y --purge autotools-dev libgeos-dev libgif-dev libgl1-mesa-dev libglu1-mesa-dev libgnutls-dev libgpg-error-dev libhdf4-alt-dev libhdf5-dev libicu-dev libidn11-dev libjasper-dev libjbig-dev libjpeg8-dev libjpeg-dev libjpeg-turbo8-dev libkrb5-dev libldap2-dev libltdl-dev liblzma-dev libmysqlclient-dev libnetcdf-dev libopenthreads-dev libp11-kit-dev libpng12-dev libpthread-stubs0-dev librtmp-dev libspatialite-dev libsqlite3-dev libssl-dev libstdc++-4.8-dev libtasn1-6-dev libtiff5-dev libwebp-dev libx11-dev libx11-xcb-dev libxau-dev libxcb1-dev libxcb-dri2-0-dev libxcb-dri3-dev libxcb-glx0-dev libxcb-present-dev libxcb-randr0-dev libxcb-render0-dev libxcb-shape0-dev libxcb-sync-dev libxcb-xfixes0-dev libxdamage-dev libxdmcp-dev libxerces-c-dev libxext-dev libxfixes-dev libxshmfence-dev libxxf86vm-dev linux-libc-dev manpages-dev mesa-common-dev libgcrypt11-dev unixodbc-dev uuid-dev x11proto-core-dev x11proto-damage-dev x11proto-dri2-dev x11proto-fixes-dev x11proto-gl-dev x11proto-input-dev x11proto-kb-dev x11proto-xext-dev x11proto-xf86vidmode-dev xtrans-dev zlib1g-dev

# installed packages
RUN apt-get remove -y --purge autoconf build-essential cmake docbook-mathml docbook-xsl libboost-dev libboost-filesystem-dev libboost-timer-dev libcgal-dev libcunit1-dev libgdal-dev libgeos++-dev libgeotiff-dev libgmp-dev libjson0-dev libjson-c-dev liblas-dev libmpfr-dev libopenscenegraph-dev libpq-dev libproj-dev libxml2-dev postgresql-server-dev-9.4 xsltproc git build-essential wget 

# additional compilation packages
RUN apt-get remove -y --purge automake m4 make

# ---------- SETUP --------------

# add a baseimage PostgreSQL init script
RUN mkdir /etc/service/postgresql
ADD postgresql.sh /etc/service/postgresql/run

# Adjust PostgreSQL configuration so that remote connections to the
# database are possible. 
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/${PG_VERSION}/main/pg_hba.conf

# And add ``listen_addresses`` to ``/etc/postgresql/9.4/main/postgresql.conf``
RUN echo "listen_addresses='*'" >> /etc/postgresql/9.4/main/postgresql.conf

# Expose PostgreSQL
EXPOSE 5432

# Add VOLUMEs to allow backup of config, logs and databases
VOLUME  ["/data", "/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]

# add database setup upon image start
ADD pgpass /root/.pgpass
RUN chmod 700 /root/.pgpass
RUN mkdir -p /etc/my_init.d
ADD init_db_script.sh /etc/my_init.d/init_db_script.sh
ADD init_db.sh /root/init_db.sh

# ---------- Final cleanup --------------
#
# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

