package com.heattrip.heat_trip_backend.OAuth.user;

public interface OAuth2UserInfo {
    String getProvider(); // e.g., "google", "kakao", "naver"
    String getProviderId(); // Unique ID for the user in the provider's system
    String getEmail(); // User's email address
    String getName(); // User's name
}   
