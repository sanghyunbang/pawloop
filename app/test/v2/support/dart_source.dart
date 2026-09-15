// 자바가 아니라 **다트 소스**를 훑는 검사들이 함께 쓰는 자리.
//
// 처음에는 `snackbar_action_must_not_persist_test` 안의 private 헬퍼였다(#531). 지도 핀
// 검사(#533)가 같은 눈을 쓰게 되면서 밖으로 뺐다 — 둘이 각자 주석을 걷으면 한쪽만 낡는다.
//
// **"무엇이 위반인가" 는 여기서 판단하지 않는다.** 이 자리는 주석을 걷어 주기만 하고,
// 무엇을 찾을지는 부르는 쪽의 규칙이다.

/// 주석을 공백으로 바꾼다 — **줄 수는 그대로 둔다**(위반을 파일:줄 로 가리켜야 고칠 자리를
/// 찾는다). 문자열 안의 `//` 와 `/*` 는 주석이 아니므로 문자열을 함께 따라간다.
String stripCommentsKeepingLines(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];

    if (c == '/' && i + 1 < source.length) {
      final n = source[i + 1];
      if (n == '/') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        continue;
      }
      if (n == '*') {
        i += 2;
        while (i < source.length && !(source[i] == '*' && i + 1 < source.length && source[i + 1] == '/')) {
          if (source[i] == '\n') out.write('\n');
          i++;
        }
        i += 2;
        continue;
      }
    }

    if (c == '"' || c == "'") {
      final triple = source.startsWith(c * 3, i);
      final quote = triple ? c * 3 : c;
      // 날 문자열(r'…') 안에서는 역슬래시가 이스케이프가 아니다. 정규식 리터럴이 전부
      // 그것이라, 여기서 안 가르면 역슬래시로 끝나는 날 문자열이 안 닫힌 것처럼 보인다.
      final raw = i > 0 && source[i - 1] == 'r';
      out.write(quote);
      i += quote.length;
      while (i < source.length && !source.startsWith(quote, i)) {
        if (!raw && source[i] == r'\') {
          i++; // 다음 글자는 따옴표여도 끝이 아니다
          if (i < source.length && source[i] == '\n') out.write('\n');
          i++;
          continue;
        }
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      out.write(quote);
      i += quote.length;
      continue;
    }

    out.write(c);
    i++;
  }
  return out.toString();
}
