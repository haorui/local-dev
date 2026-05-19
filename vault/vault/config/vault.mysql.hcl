ui            = true
api_addr      = "http://127.0.0.1:8200"
disable_mlock = true

storage "mysql" {
  username = "root"
  password = "Zonesec2024."
  database = "vault"
  address  = "192.168.3.123:3306"
}
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable = "false"
}
