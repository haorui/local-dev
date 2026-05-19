# 1. 生成 bcrypt 密码
python3 -c 'import bcrypt; print(bcrypt.hashpw(b"admin123", bcrypt.gensalt()).decode("utf-8"))'

# 2.创建文件 etc/password.db
# admin:$2b$12$EXAMPLE_HASH_FROM_PYTHON_OUTPUT_HERE
