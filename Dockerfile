FROM nvidia/cuda:10.0-devel-ubuntu18.04 AS build

WORKDIR /root

# Install apt packages.
ENV DEBIAN_FRONTEND noninteractive
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE 1
RUN apt-get update && apt-get install -y --no-install-recommends apt-utils \
 && echo "deb https://dl.bintray.com/sbt/debian /" > /etc/apt/sources.list.d/sbt.list \
 && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 2EE0EA64E40A89B84B2DF73499E82A75642AC823 \
 && apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    git \
    openjdk-8-jdk \
    python \
    sbt \
    wget \
 && rm -rf /var/lib/apt/lists/*

# Install cuDF.
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
 && bash Miniconda3-latest-Linux-x86_64.sh -b \
 && miniconda3/bin/conda install -y -c nvidia/label/cf201901 -c rapidsai/label/cf201901 -c numba -c conda-forge/label/cf201901 -c defaults cudf=0.4.0

# Install Maven (`apt install maven` installs JDK 11, but we need to stay with JDK 8).
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64
ENV MAVEN_VERSION 3.6.0
RUN wget -q https://www-us.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
 && tar xzf apache-maven-${MAVEN_VERSION}-bin.tar.gz -C /opt \
 && ln -s /opt/apache-maven-${MAVEN_VERSION} /opt/maven
ENV M2_HOME /opt/maven
ENV MAVEN_HOME /opt/maven
ENV PATH ${M2_HOME}/bin:${PATH}

# Build XGBoost.
RUN git clone -b spark-gpu-example --recurse-submodules https://github.com/rongou/xgboost.git
ENV GDF_ROOT /root/miniconda3
WORKDIR /root/xgboost/jvm-packages
RUN mvn -DskipTests install

# Build Spark examples.
COPY build.sbt /root/spark-examples/
COPY mortgage /root/spark-examples/mortgage
COPY project /root/spark-examples/project
WORKDIR /root/spark-examples
RUN sbt assembly

# TODO(rongou): move this base image to rapidsai.
FROM rongou/spark-gpu:a4e48359ac-2.11-kubernetes

# Reset to root to run installation tasks
USER 0

# Install additional packags for XGBoost.
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends apt-utils \
 && apt-get install -y --no-install-recommends python libgomp1 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /root/spark-examples/mortgage/target/scala-2.11/mortgage-assembly-0.1.0-SNAPSHOT.jar /opt/spark/examples/jars

# Specify the User that the actual main process will run as
USER ${spark_uid}