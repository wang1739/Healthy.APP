package com.lightbite.healthy.auth;

public interface WechatIdentityProvider {
    String verify(String authorizationCode);
}
