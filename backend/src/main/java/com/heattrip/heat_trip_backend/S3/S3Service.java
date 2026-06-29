// // S3FileStorageService.java
// package com.heattrip.heat_trip_backend.S3;

// import com.amazonaws.services.s3.AmazonS3;
// import com.amazonaws.services.s3.model.*;
// import java.io.*; import java.net.URL; import java.time.Duration; import java.util.Collection;
// import org.springframework.beans.factory.annotation.Value; import org.springframework.stereotype.Service; import org.springframework.web.multipart.MultipartFile;

// @Service
// public class S3FileStorageService implements FileStorage {

//   private final AmazonS3 s3; private final KeyStrategy keyStrategy; private final UploadValidator validator;
//   @Value("${cloud.aws.s3.bucket}") private String bucket;
//   @Value("${cloud.aws.cloudfront.domain}") private String cf;

//   public S3FileStorageService(AmazonS3 s3, KeyStrategy keyStrategy, UploadValidator validator){
//     this.s3=s3; this.keyStrategy=keyStrategy; this.validator=validator;
//   }

//   @Override public StoredObject upload(MultipartFile file, UploadRequest req){
//     validator.validate(file, req);
//     String key = keyStrategy.buildKey(file, req);
//     ObjectMetadata meta = new ObjectMetadata();
//     meta.setContentLength(file.getSize()); meta.setContentType(file.getContentType());
//     meta.setCacheControl("public, max-age=31536000, immutable");
//     try(var in = file.getInputStream()){
//       s3.putObject(new PutObjectRequest(bucket, key, in, meta));
//     }catch(IOException e){ throw new RuntimeException("S3 업로드 실패", e); }
//     return new StoredObject(key, UrlMapper.cfUrl(cf,key), file.getContentType(), file.getSize());
//   }

//   @Override public String publicUrl(String key){ return UrlMapper.cfUrl(cf, key); }
//   @Override public boolean exists(String key){ return s3.doesObjectExist(bucket, key); }

//   @Override public byte[] downloadBytes(String key){
//     try(S3Object obj = s3.getObject(bucket,key); S3ObjectInputStream in = obj.getObjectContent(); ByteArrayOutputStream out = new ByteArrayOutputStream()){
//       in.transferTo(out); return out.toByteArray();
//     }catch(IOException e){ throw new RuntimeException("S3 다운로드 실패", e); }
//   }

//   @Override public InputStream openStream(String key){ return s3.getObject(bucket,key).getObjectContent(); }

//   @Override public URL presignedUrl(String key, Duration ttl){
//     var exp = new java.util.Date(System.currentTimeMillis()+ttl.toMillis());
//     return s3.generatePresignedUrl(new GeneratePresignedUrlRequest(bucket,key).withMethod(HttpMethod.GET).withExpiration(exp));
//   }

//   @Override public void delete(String key){ s3.deleteObject(bucket,key); }

//   @Override public void deleteAll(Collection<String> keys){
//     if(keys==null||keys.isEmpty()) return;
//     s3.deleteObjects(new DeleteObjectsRequest(bucket).withKeys(keys.stream().map(DeleteObjectsRequest.KeyVersion::new).toList()));
//   }

//   /** Update: 새 키로 업로드 → 이전 키 삭제(캐시 일관성/롤백 용이) */
//   @Override public StoredObject replace(String oldKey, MultipartFile file, UploadRequest req){
//     StoredObject neo = upload(file, req);  // 새로 업로드
//     if(oldKey!=null && !oldKey.isBlank()) { try { delete(oldKey);} catch(Exception ignored){} }
//     return neo;
//   }
// }
