FROM gliderlabs/alpine:3.2
MAINTAINER Alexander Tsirel <noma4i@gmail.com>

RUN apk --update add tor haproxy ruby wget curl zlib libyaml --update-cache --repository http://dl-3.alpinelinux.org/alpine/edge/testing/ --allow-untrusted
RUN gem install excon -v 0.44.4 --no-ri --no-rdoc

RUN apk add -U build-base openssl \
    && wget https://github.com/jech/polipo/archive/master.zip -O polipo.zip \
    && unzip polipo.zip \
    && cd polipo-master \
    && make \
    && install polipo /usr/local/bin/ \
    && cd .. \
    && rm -rf polipo.zip polipo-master \
    && mkdir -p /usr/share/polipo/www /var/cache/polipo \
    && apk del build-base openssl \
    && rm -rf /var/cache/apk/*

ADD bootstrap.rb /opt/bootstrap.rb
RUN chmod +x /opt/bootstrap.rb

ADD haproxy.cfg.erb /opt/haproxy.cfg.erb
ADD torrc.erb /opt/torrc.erb

EXPOSE 3128 1936

CMD /opt/bootstrap.rb