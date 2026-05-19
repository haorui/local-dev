FROM ubuntu:20.04
ENV DEBIAN_FRONTEND noninteractive
RUN sed -i s@/archive.ubuntu.com/@/mirrors.aliyun.com/@g /etc/apt/sources.list
RUN sed -i s@/security.ubuntu.com/@/mirrors.aliyun.com/@g /etc/apt/sources.list
RUN apt clean
RUN apt update
RUN apt install -y ntp python3-dev python3-pip python3-wheel python3-setuptools python3-pkg-resources krb5-admin-server krb5-kdc
RUN apt install vim -y
RUN rm -rf /var/lib/apt/lists/*
RUN mkdir -p /var/log/supervisord/ /app /keytabs
RUN pip3 install supervisor==4.2.4
COPY ./server/krb5.conf /etc/krb5kdc/kdc.conf
COPY ./server/kadm5.acl /etc/krb5kdc/kadm5.acl
COPY ./client/krb5.conf /etc/krb5.conf
COPY ./start.sh /app/start.sh
COPY ./supervisord.conf /etc/supervisord.conf
WORKDIR /app
CMD ["/bin/bash", "/app/start.sh"]
