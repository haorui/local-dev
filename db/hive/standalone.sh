# This is lightweight and for a quick setup, it uses Derby as metastore db.
# docker run -d -p 10000:10000 -p 10002:10002 --env SERVICE_NAME=hiveserver2 --name hiveserver2 apache/hive:4.2.0

# docker run -d -p 9083:9083 --net dev_db_network --env SERVICE_NAME=metastore --name metastore-standalone apache/hive:4.2.0

# docker run -d -p 9083:9083 --net dev_db_network --env SERVICE_NAME=metastore --env DB_DRIVER=postgres \
#  --env SERVICE_OPTS="-Djavax.jdo.option.ConnectionDriverName=org.postgresql.Driver -Djavax.jdo.option.ConnectionURL=jdbc:postgresql://pgvector:5432/metastore_db -Djavax.jdo.option.ConnectionUserName=postgres -Djavax.jdo.option.ConnectionPassword=Zonesec2024." \
# --mount source=warehouse,target=/opt/hive/data/warehouse \
# --volume ./conf/jars/postgresql-42.7.4.jar:/opt/hive/lib/postgresql-42.7.4.jar \
# --name metastore-standalone apache/hive:4.2.0

docker run -d -p 10000:10000 -p 10002:10002 --net dev_db_network --env SERVICE_NAME=hiveserver2 \
--env SERVICE_OPTS="-Dhive.metastore.uris=thrift://metastore-standalone:9083" \
--env IS_RESUME="true" \
--name hiveserver2-standalone apache/hive:4.2.0
