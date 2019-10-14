FROM postgres:latest

# in the docker initialization, we do not build the data
ENV BUILD_MIMIC 0
COPY . /docker-entrypoint-initdb.d/buildmimic
COPY docker/setup.sh /docker-entrypoint-initdb.d/

# make a directory for the data
RUN mkdir /mimic_data
