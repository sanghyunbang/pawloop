package com.heattrip.heat_trip_backend.place.layer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import javax.xml.stream.XMLInputFactory;
import javax.xml.stream.XMLStreamConstants;
import javax.xml.stream.XMLStreamReader;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/**
 * 공공데이터포털 게이트웨이({@code apis.data.go.kr})의 응답 봉투를 읽는다 — 이슈 #291.
 *
 * <p>KTO({@code KtoApiClient})와 같은 봉투를 쓰는 API 가 둘 더 붙었다(행정안전부 인허가 ·
 * 두루누비). 봉투는 세 가지 모양으로 온다.
 * <ol>
 *   <li>정상 — {@code response.header.resultCode} + {@code response.body.items.item[]}.
 *       {@code item} 은 하나면 객체, 여럿이면 배열이다.</li>
 *   <li>게이트웨이 거절 — HTTP 4xx + {@code OpenAPI_ServiceResponse.cmmMsgHeader.returnReasonCode}.
 *       키 미등록(30)·트래픽 초과(22)가 여기로 온다.</li>
 *   <li><b>XML</b> — 어떤 서비스는 {@code _type=json} 을 무시하거나 오류를 XML 로 준다.
 *       같은 트리를 XML 로 받으면 JSON 으로 눕혀 같은 길로 보낸다.</li>
 * </ol>
 *
 * <p>정상 코드가 서비스마다 다르다. KTO 는 {@code 0000}, 행정안전부 게이트웨이는 {@code 00} 을
 * 쓴다고 명세가 적는다. 그래서 여기서는 코드를 판정하지 않고 <b>그대로 넘긴다</b> — 호출부가
 * 자기 서비스의 정상값과 견준다.
 */
final class DataGoKrEnvelope {

    /** 읽은 봉투. {@code gatewayError} 가 있으면 나머지는 의미가 없다. */
    record Parsed(String gatewayError, String gatewayMessage,
                  String resultCode, String resultMsg,
                  List<JsonNode> items, int totalCount, boolean hasBody) {

        boolean gatewayRejected() {
            return gatewayError != null;
        }
    }

    /** 서비스가 "정상" 이라고 말하는 코드들. 서비스마다 자릿수가 다르다. */
    static final Set<String> OK_CODES = Set.of("0000", "00", "0");

    private DataGoKrEnvelope() {
    }

    static Parsed parse(ObjectMapper objectMapper, String raw) throws Exception {
        String body = raw == null ? "" : raw.strip();
        JsonNode root = body.startsWith("<") ? XmlToJson.parse(body) : objectMapper.readTree(body);

        JsonNode gateway = root.path("OpenAPI_ServiceResponse").path("cmmMsgHeader");
        if (!gateway.isMissingNode()) {
            return new Parsed(gateway.path("returnReasonCode").asText(null),
                    gateway.path("returnAuthMsg").asText(""),
                    null, null, List.of(), 0, false);
        }

        JsonNode response = root.path("response");
        JsonNode header = response.path("header");
        JsonNode bodyNode = response.path("body");
        String resultCode = header.path("resultCode").asText(null);
        String resultMsg = header.path("resultMsg").asText("");

        return new Parsed(null, null, resultCode, resultMsg,
                items(bodyNode), bodyNode.path("totalCount").asInt(0), !bodyNode.isMissingNode());
    }

    /** {@code body.items.item} 을 배열로. {@code items} 가 빈 문자열이면 0건이다. */
    private static List<JsonNode> items(JsonNode body) {
        JsonNode items = body.path("items");
        JsonNode item = items.isObject() ? items.path("item") : items;
        if (item.isArray()) {
            List<JsonNode> out = new ArrayList<>(item.size());
            item.forEach(out::add);
            return out;
        }
        return item.isObject() ? List.of(item) : List.of();
    }

    /**
     * XML 트리를 JSON 트리로. 같은 이름의 형제는 배열, 잎은 문자열이다.
     *
     * <p>Jackson XML 모듈을 들이지 않는 이유: 이 한 곳을 위해 의존성을 하나 더 다는 것보다
     * JDK 의 StAX 40줄이 싸다. 속성은 버린다 — 이 봉투들은 속성을 안 쓴다.
     */
    static final class XmlToJson {

        private XmlToJson() {
        }

        static JsonNode parse(String xml) throws Exception {
            XMLInputFactory factory = XMLInputFactory.newFactory();
            // 외부 엔티티를 끈다 — 남의 서버가 주는 XML 이다.
            factory.setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES, false);
            factory.setProperty(XMLInputFactory.SUPPORT_DTD, false);
            XMLStreamReader reader = factory.createXMLStreamReader(new StringReader(xml));
            try {
                ObjectMapper mapper = new ObjectMapper();
                ObjectNode root = mapper.createObjectNode();
                while (reader.hasNext()) {
                    if (reader.next() == XMLStreamConstants.START_ELEMENT) {
                        put(root, reader.getLocalName(), element(reader, mapper));
                    }
                }
                return root;
            } finally {
                reader.close();
            }
        }

        /** 현재 START_ELEMENT 의 내용을 읽고 END_ELEMENT 에서 멈춘다. */
        private static JsonNode element(XMLStreamReader reader, ObjectMapper mapper) throws Exception {
            ObjectNode children = mapper.createObjectNode();
            StringBuilder text = new StringBuilder();
            while (reader.hasNext()) {
                int event = reader.next();
                if (event == XMLStreamConstants.START_ELEMENT) {
                    put(children, reader.getLocalName(), element(reader, mapper));
                } else if (event == XMLStreamConstants.CHARACTERS || event == XMLStreamConstants.CDATA) {
                    text.append(reader.getText());
                } else if (event == XMLStreamConstants.END_ELEMENT) {
                    break;
                }
            }
            return children.isEmpty() ? mapper.getNodeFactory().textNode(text.toString().strip()) : children;
        }

        private static void put(ObjectNode parent, String name, JsonNode value) {
            JsonNode existing = parent.get(name);
            if (existing == null) {
                parent.set(name, value);
            } else if (existing.isArray()) {
                ((ArrayNode) existing).add(value);
            } else {
                ArrayNode array = parent.putArray(name);
                array.add(existing);
                array.add(value);
            }
        }
    }
}
