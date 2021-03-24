FROM ubuntu:20.04
MAINTAINER mongenae@its.jnj.com

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/London

ENV STAR_VERSION 2.7.8a
ENV RSEM_VERSION 1.3.3
ENV ARRIBA_VERSION 2.1.0
ENV SAMBLASTER_VERSION 0.1.26
ENV PICARD_VERSION 2.25.0

RUN apt-get update && \
    apt-get upgrade -y 

RUN apt-get install -y zlibc zlib1g zlib1g-dev make gcc g++ wget
RUN apt-get install -y r-base-core libboost-dev
RUN apt-get install -y libncurses-dev libbz2-dev liblzma-dev
RUN apt-get install -y bowtie bowtie2

RUN apt-get install -y \
      build-essential \
      samtools \
      r-base \
      ca-certificates \
      libcurl4-openssl-dev \
      libxml2-dev \
      wget \
      samtools \
      openjdk-11-jre \
      zlibc \
      zlib1g \
      zlib1g-dev \
      locales

WORKDIR /home

RUN wget --no-check-certificate https://github.com/alexdobin/STAR/archive/${STAR_VERSION}.tar.gz
RUN tar -xzf ${STAR_VERSION}.tar.gz
WORKDIR /home/STAR-${STAR_VERSION}/source
RUN make STAR
ENV PATH /home/STAR-${STAR_VERSION}/source:${PATH}

WORKDIR /home

RUN wget --no-check-certificate https://github.com/deweylab/RSEM/archive/refs/tags/v${RSEM_VERSION}.tar.gz
RUN tar -xzf v${RSEM_VERSION}.tar.gz
WORKDIR /home/RSEM-${RSEM_VERSION}
RUN make
RUN make ebseq
ENV PATH="/home/RSEM-${RSEM_VERSION}":$PATH

# Install Required Arriba R packages
RUN Rscript -e 'install.packages("circlize", repos="http://cran.r-project.org")'
RUN Rscript -e 'install.packages("BiocManager"); BiocManager::install(c("GenomicRanges", "GenomicAlignments"))'

WORKDIR /home

# Install and build Arriba
RUN wget --no-check-certificate https://github.com/suhrig/arriba/releases/download/v${ARRIBA_VERSION}/arriba_v${ARRIBA_VERSION}.tar.gz
RUN tar -xzf arriba_v${ARRIBA_VERSION}.tar.gz


WORKDIR /home/arriba_v${ARRIBA_VERSION}
RUN make
ENV PATH="/home/arriba_v${ARRIBA_VERSION}":$PATH

WORKDIR /home/

# Install and build samblaster
RUN wget --no-check-certificate https://github.com/GregoryFaust/samblaster/releases/download/v.${SAMBLASTER_VERSION}/samblaster-v.${SAMBLASTER_VERSION}.tar.gz && \
    tar -xzf samblaster-v.${SAMBLASTER_VERSION}.tar.gz && \
    cd /home/samblaster-v.${SAMBLASTER_VERSION} && \
    make

 ENV PATH="/home/samblaster-v.${SAMBLASTER_VERSION}":$PATH

# Adding Picard Cloud JAR

RUN mkdir /home/picard
WORKDIR /home/picard
RUN wget --no-check-certificate https://github.com/broadinstitute/picard/releases/download/${PICARD_VERSION}/picardcloud.jar
RUN chmod a+rx /home/picard/*.jar

ENV PATH="/home/picard/":$PATH


# Arriba Wrapper Scripts
RUN mkdir /home/bin
WORKDIR /home/bin

# download_references.sh wrapper
RUN echo '#!/bin/bash\n\
cd /references\n\
/home/arriba_v${ARRIBA_VERSION}/download_references.sh $1 && \\\n\
ASSEMBLY=$(sed -e "s/viral+.*//" -e "s/+.*//" <<<"$1") && \\\n\
cp /home/arriba_v${ARRIBA_VERSION}/database/*$ASSEMBLY* /references' > /usr/local/bin/download_references.sh && \
chmod a+x /usr/local/bin/download_references.sh

# run_arriba.sh wrapper
RUN echo '#!/bin/bash\n\
cd /home/arriba_v${ARRIBA_VERSION}/test/ && \\\n\
/home/arriba_v${ARRIBA_VERSION}/run_arriba.sh /references/STAR_index_* /references/*.gtf /references/*.fa /references/blacklist_*.tsv.gz /references/known_fusions_*.tsv.gz /references/protein_domains_*.gff3 ${THREADS-8} read1.fastq.gz $(ls read2.fastq.gz 2> /dev/null)' > /usr/local/bin/arriba.sh && \
chmod a+x /usr/local/bin/arriba.sh

# draw_fusions.R wrapper
RUN echo '#!/bin/bash\n\
Rscript /home/arriba_v${ARRIBA_VERSION}/draw_fusions.R --annotation=$(ls /references/*.gtf) --fusions=/home/arriba_v${ARRIBA_VERSION}/test/fusions.tsv --output=fusions.pdf --proteinDomains=$(ls /references/protein_domains_*.gff3) --alignments=Aligned.sortedByCoord.out.bam --cytobands=$(ls /references/cytobands_*.tsv)' > /usr/local/bin/draw_fusions.sh && \
chmod a+x /usr/local/bin/draw_fusions.sh

# Configure "locale", see https://github.com/rocker-org/rocker/issues/19
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen en_US.utf8 \
    && /usr/sbin/update-locale LANG=en_US.UTF-8

# Add Tools to PATH
ENV PICARDJARPATH=/home/picard
ENV PATH="/home/bin":$PATH


RUN echo "export PATH=$PATH" > /etc/environment
RUN echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" > /etc/environment
