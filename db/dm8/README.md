https://hub.docker.com/r/onlyoffice/damengdb

Can be runned with:

docker run -d -p 5236:5236 --restart=always --name dm8_01 --privileged=true -e PAGE_SIZE=16 -e LD_LIBRARY_PATH=/opt/dmdbms/bin -e INSTANCE_NAME=dm8_01 -v /data/dm8_01:/opt/dmdbms/data onlyoffice/damengdb:8.1.3
NOTE: Different versions have different login credentials for the database.

8.1.3:

SYSDBA/SYSDBA_dm001
