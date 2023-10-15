> **Note:** Getting debezium connector work with postgres is pain. There are lots of things that we need to take care about -

1. WAL Level - should be `logical`.
2. `max_wal_senders` - should be greater than 0.
3. `max_replication_slots` - should be greater than 0.
4. `decoderbufs` | `pgoutput` plugin - should be installed.

Due to all of this, I have used `debezium/postgres:15.0` instead of the official docker image of postgres.


---
## 1️⃣ Setting up the source (Postgres)
1. Simulate database changes -

    ```bash
    docker exec postgres /data/populate-orders.sh
    ```

2. Monitor the database changes
    ```bash
    watch -n 1 -x docker exec -t postgres bash -c 'echo "SELECT * FROM public.orders ORDER BY created_at DESC LIMIT 1" | psql -x -h localhost -U postgresuser -d kafka-demo'
    ```

---
## 2️⃣ Setting up the connectors (KafkaConnect)
1. Check installed connectors -

    ```bash
    curl -s http://localhost:8083/connector-plugins | jq
    ```

2. Create the source connector -
    
    ```bash
    curl -i -X PUT -H  "Content-Type:application/json" \
        http://localhost:8083/connectors/source-postgresql-debezium-orders/config \
        -d ' {
            "name": "source-postgresql-debezium-orders",
            "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
            "database.hostname": "postgres",
            "database.port": "5432",
            "database.dbname": "kafka-demo",
            "database.user": "postgresuser",
            "database.password": "somesupersecretpassword",
            "database.history.kafka.bootstrap.servers": "broker:29092",
            "database.history.kafka.topic": "dbhistory.demo" ,
            "decimal.handling.mode": "double",
            "heartbeat.interval.ms": "5000",
            "heartbeat.action.query": "INSERT INTO test_heartbeat_table (text) VALUES ('test_heartbeat')",
            "include.schema.changes": "true",
            "schema.include.list": "public",
            "table.whitelist": "public.orders",
            "topic.prefix": "postgresql-debezium-",
            "transforms": "unwrap,addTopicPrefix",
            "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
            "transforms.addTopicPrefix.type":"org.apache.kafka.connect.transforms.RegexRouter",
            "transforms.addTopicPrefix.regex":"(.*)",
            "transforms.addTopicPrefix.replacement":"postgresql-debezium-$1"
        }'
    ```

> Heartbeat messages are needed when there are many updates in a database that is being tracked but only a tiny number of updates are related to the table(s) and schema(s) for which the connector is capturing changes. In short, it is used to solve the `WAL Disk Space` issue. [Read more](https://debezium.io/documentation/reference/2.2/connectors/postgresql.html#postgresql-wal-disk-space). Assume, it's a sanity thing & always include it


1. Check the status of the connector

    ```bash
        curl -s "http://localhost:8083/connectors?expand=info&expand=status" | jq
    ```

2. [OPTIONAL] For me, one of the connector task status was `FAILED`. So, I deleted the connector and recreated it by repeating step 2.

    ```bash
        curl -X DELETE http://localhost:8083/connectors/source-postgresql-debezium-orders
    ```

3. View the Kafka topic
    *List all the topics*
        
        ```bash
        docker exec -it broker kafka-topics --list --bootstrap-server broker:29092
        ```

    *View the topic content*
        
        ```bash
        docker exec kcat kcat -b broker:29092 -C -t postgresql-debezium-postgresql-debezium-.public.orders -o -1 -q | jq '"id: \(.payload.id)", "created_at: \(.payload.created_at)"'
        ```

---
## 3️⃣ Setting up the sink (ElasticSearch)

1. **Stream the data from Kafka topic to ElasticSearch**
    ```bash
    curl -i -X PUT -H  "Content-Type:application/json" \
        http://localhost:8083/connectors/sink-elastic-orders-00/config \
        -d '{
            "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
            "topics": "postgresql-debezium-postgresql-debezium-.public.orders",
            "connection.url": "http://elasticsearch:9200",
            "type.name": "type.name=kafkaconnect"
        }'
    ```

2. View in Kibana
    * Open Kibana in browser - http://localhost:5601
    * Create an index pattern - `postgresql-debezium-postgresql-debezium-.public.orders`
    * View the data in the index
  
