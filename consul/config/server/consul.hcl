
datacenter = "local"
data_dir = "/opt/consul"
encrypt = "VHItfpscoN5CQaJhoTZp9VhAWQc6MCARUZMikyGOjGM="
ca_file = "/etc/consul.d/server/certs/consul-agent-ca.pem"
cert_file = "/etc/consul.d/server/certs/local-server-consul-0.pem"
key_file = "/etc/consul.d/server/certs/local-server-consul-0-key.pem"
verify_incoming = true
verify_outgoing = true
verify_server_hostname = true

acl = {
    enabled = true
    default_policy = "allow"
    enable_token_persistence = true
}

performance {
    raft_multiplier = 1
}
