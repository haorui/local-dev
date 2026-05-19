# echo "Begin"
#   docker secret rm nginx_key &>/dev/null
#   docker secret create nginx_key "selfsigned.key"
#   
#   docker secret rm nginx_cert &>/dev/null
#   docker secret create nginx_cert "selfsigned.crt"
#     
#   docker config rm nginx.conf &>/dev/null
#   docker config create nginx.conf ./nginx.conf
#   
#   docker config rm nginx_sso.conf &>/dev/null
#   docker config create nginx_sso.conf ./conf.d/sso.conf
#   
#   docker network rm dbserver &>/dev/null
#   docker network create -d overlay dbserver
#
# echo "End"
