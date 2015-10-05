# tor-proxy-rotator
Docker container to spin Tor proxy rotation

`docker run -p 3128:3128 -p 1936:1936 --env tors=20 --env geo=ru,ua noma4i/tor-proxy-rotator`
