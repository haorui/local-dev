import org.apache.zookeeper.*;
import org.apache.zookeeper.data.ACL;
import org.apache.zookeeper.data.Id;
import org.apache.zookeeper.ZooDefs;
import java.util.ArrayList;
import java.util.List;
import javax.security.auth.login.Configuration;
import java.io.File;

public class create_node {
    public static void main(String[] args) throws Exception {
        // Set JAAS configuration
        System.setProperty("java.security.auth.login.config", "/opt/hive/conf/zk_client_jaas.conf");
        System.setProperty("java.security.krb5.conf", "/etc/krb5.conf");
        System.setProperty("zookeeper.sasl.client", "true");
        System.setProperty("zookeeper.sasl.clientconfig", "HiveZooKeeperClient");
        
        // Connect to ZooKeeper
        ZooKeeper zk = new ZooKeeper("zoo1:2181", 30000, new Watcher() {
            public void process(WatchedEvent event) {
                System.out.println("Event: " + event);
            }
        });
        
        // Wait for connection
        Thread.sleep(2000);
        
        // Create ACL: world:anyone:r + sasl:hive/hadoop@TEST.COM:cdrwa
        List<ACL> acls = new ArrayList<ACL>();
        acls.addAll(ZooDefs.Ids.READ_ACL_UNSAFE); // world:anyone:r
        acls.add(new ACL(ZooDefs.Perms.ALL, new Id("sasl", "hive/hadoop@TEST.COM")));
        
        try {
            // Create /hiveserver2 node if it doesn't exist
            if (zk.exists("/hiveserver2", false) == null) {
                String path = zk.create("/hiveserver2", new byte[0], acls, CreateMode.PERSISTENT);
                System.out.println("Created node: " + path);
            } else {
                System.out.println("Node /hiveserver2 already exists");
                // Set ACL
                zk.setACL("/hiveserver2", acls, -1);
                System.out.println("Updated ACL for /hiveserver2");
            }
            
            // List children
            List<String> children = zk.getChildren("/hiveserver2", false);
            System.out.println("Children of /hiveserver2: " + children);
            
        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            e.printStackTrace();
        } finally {
            zk.close();
        }
    }
}

