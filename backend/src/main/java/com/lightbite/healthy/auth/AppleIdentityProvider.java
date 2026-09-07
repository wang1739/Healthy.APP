package com.lightbite.healthy.auth;

public interface AppleIdentityProvider {
    String verify(String identityToken);
}
