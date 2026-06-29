package com.heattrip.heat_trip_backend.tour.util;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;

import com.heattrip.heat_trip_backend.tour.dto.PlaceItemDto;

public class XmlParser {
    
    public List<PlaceItemDto> parseItems(String xml) throws Exception {

        List<PlaceItemDto> list = new ArrayList<>();

        //DocumentBuilderFactory 클래스로 XML 문서에서 DOM 오브젝트 트리를 생성하는 parser를 얻을 수 있음
        DocumentBuilderFactory f = DocumentBuilderFactory.newInstance();
        
        DocumentBuilder b = f.newDocumentBuilder();

        try (InputStream is = new ByteArrayInputStream(xml.getBytes())) {
            Document doc = b.parse(is);
            doc.getDocumentElement().normalize();
            NodeList items = doc.getElementsByTagName("item");

            for (int i = 0; i < items.getLength(); i++) {
                Element e = (Element) items.item(i);
                PlaceItemDto dto = PlaceItemDto.builder()
                    .contentid(getLong(e, "contentid"))
                    .title(getStr(e, "title"))
                    .addr1(getStr(e, "addr1"))
                    .addr2(getStr(e, "addr2"))
                    .zipcode(getStr(e, "zipcode"))
                    .mapx(getDouble(e, "mapx"))
                    .mapy(getDouble(e, "mapy"))
                    .firstimage(getStr(e, "firstimage"))
                    .firstimage2(getStr(e, "firstimage2"))
                    .cat1(getStr(e, "cat1"))
                    .cat2(getStr(e, "cat2"))
                    .cat3(getStr(e, "cat3"))
                    .areacode(getInt(e, "areacode"))
                    .sigungucode(getInt(e, "sigungucode"))
                    .lDongRegnCd(getInt(e, "lDongRegnCd"))
                    .lDongSignguCd(getInt(e, "lDongSignguCd"))
                    .tel(getStr(e, "tel"))
                    .contenttypeid(getStr(e, "contenttypeid"))
                    .createdtime(parseLocalDateTime(getStr(e, "createdtime")))
                    .modifiedtime(parseLocalDateTime(getStr(e, "modifiedtime")))
                    .mlevel(getStr(e, "mlevel"))
                    .build();
                list.add(dto);
            }
        }

        return list;        
    }

    private String getStr(Element e, String tag) {
        NodeList nl = e.getElementsByTagName(tag);
        return nl.getLength() == 0 ? null : nl.item(0).getTextContent();
    }
    private Long getLong(Element e, String tag) {
        String s = getStr(e, tag);
        return (s == null || s.isBlank()) ? null : Long.parseLong(s);
        }
    private Integer getInt(Element e, String tag) {
        String s = getStr(e, tag);
        return (s == null || s.isBlank()) ? null : Integer.parseInt(s);
    }
    private Double getDouble(Element e, String tag) {
        String s = getStr(e, tag);
        return (s == null || s.isBlank()) ? null : Double.parseDouble(s);
    }

    private java.time.LocalDateTime parseLocalDateTime(String s) {
        if (s == null || s.isBlank()) return null;
        // Adjust the pattern according to your XML date format, e.g. "yyyy-MM-dd'T'HH:mm:ss"
        java.time.format.DateTimeFormatter formatter = java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss");
        return java.time.LocalDateTime.parse(s, formatter);
    }

}
