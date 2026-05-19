# Replace my_keystore_password with your desired password
keytool -genkeypair \
    -alias trino \
    -keyalg RSA \
    -keystore trino.jks \
    -keypass amdin123 \
    -storepass admin123 \
    -dname "CN=localhost, OU=Dev, O=MyCompany, L=Tokyo, S=Tokyo, C=JP" \
    -validity 3650
