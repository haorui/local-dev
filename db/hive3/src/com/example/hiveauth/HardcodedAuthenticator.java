package com.example.hiveauth;

import javax.security.sasl.AuthenticationException;
import org.apache.hive.service.auth.PasswdAuthenticationProvider;

/**
 * Minimal username/password authenticator for HiveServer2.
 * Credentials can be overridden via environment variables:
 *   HIVE_AUTH_USER     (default: hive)
 *   HIVE_AUTH_PASSWORD (default: hive123)
 */
public class HardcodedAuthenticator implements PasswdAuthenticationProvider {

  private static final String EXPECTED_USER =
      envOrDefault("HIVE_AUTH_USER", "hive");
  private static final String EXPECTED_PASSWORD =
      envOrDefault("HIVE_AUTH_PASSWORD", "hive123");

  @Override
  public void Authenticate(String user, String password) throws AuthenticationException {
    if (EXPECTED_USER.equals(user) && EXPECTED_PASSWORD.equals(password)) {
      return;
    }
    throw new AuthenticationException("Invalid username or password");
  }

  private static String envOrDefault(String name, String defaultValue) {
    String v = System.getenv(name);
    return (v == null || v.isEmpty()) ? defaultValue : v;
  }
}
