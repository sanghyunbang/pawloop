// 이 클래스는 "Google 소셜 로그인"을 통해 받은 사용자 정보를 정리해서 사용할 수 있게 도와주는 클래스입니다.
// 소셜 로그인 응답은 JSON 형식인데, 그걸 자바 객체 형태로 쉽게 다룰 수 있도록 래핑(wrapping)합니다.

package com.heattrip.heat_trip_backend.OAuth.user;

import java.util.Map;

// GoogleOAuth2User는 OAuth2UserInfo라는 공통 인터페이스를 구현.
public class GoogleOAuth2User implements OAuth2UserInfo {

    // Google에서 받아온 사용자 정보를 담는 변수입니다.
    // 예: attributes.get("email") → "abc@gmail.com"

    private final Map<String, Object> attributes;

    // '생성자(Constructor)'입니다.
    // 클래스가 처음 생성될 때 실행되는 특별한 메서드입니다.
    // => new GoogleOAuth2User(googleAttributes) 와 같이 객체를 만들 때 호출됩니다.
    //
    // 생성자는 주로 클래스의 초기값을 설정하는 데 사용됩니다.
    // 여기서는 Google에서 받아온 사용자 정보를 this.attributes에 저장합니다.
    public GoogleOAuth2User(Map<String, Object> attributes) {
        this.attributes = attributes;
    }

    // 오버라이드를 통해 상속받은 메서드를 다시 정의합니다.
    // 이 메서드는 어떤 소셜 로그인 제공자인지를 문자열로 반환하며, 여기선 "google"을 반환합니다.
    @Override
    public String getProvider() {
        return "google";
    }

    // Google에서 받은 사용자 ID 중, 고유 식별자 역할을 하는 "sub" 키의 값을 반환합니다.
    // (예: "103284713847102934719")
    @Override
    public String getProviderId() {
        return (String) attributes.get("sub");
    }

    // 사용자의 이메일 주소를 반환합니다. 예: "johndoe@gmail.com"
    @Override
    public String getEmail() {
        return (String) attributes.get("email");
    }

    // 사용자의 이름을 반환합니다. 예: "John Doe"
    @Override
    public String getName() {
        return (String) attributes.get("name");
    }

    // 전체 사용자 정보(Map)를 반환합니다.
    // 필요 시 전체 원본 JSON 데이터에 접근할 수 있도록 합니다.
    public Map<String, Object> getAttributes() {
        return attributes;
    }    
    
}
