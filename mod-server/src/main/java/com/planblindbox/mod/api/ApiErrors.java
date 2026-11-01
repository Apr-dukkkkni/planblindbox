package com.planblindbox.mod.api;

import com.planblindbox.mod.domain.ApiError;
import com.planblindbox.mod.domain.BadRequest;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

@RestControllerAdvice
public class ApiErrors {
    @ExceptionHandler(BadRequest.class)
    ResponseEntity<ApiError> bad(BadRequest e) {return ResponseEntity.badRequest().body(new ApiError("BAD_REQUEST", e.getMessage()));}
    @ExceptionHandler(DuplicateKeyException.class)
    ResponseEntity<ApiError> conflict(DuplicateKeyException e) {return ResponseEntity.status(409).body(new ApiError("CONFLICT", "记录冲突，请重试"));}
    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<ApiError> malformed(HttpMessageNotReadableException e) {return ResponseEntity.badRequest().body(new ApiError("INVALID_JSON", "请求 JSON 格式不正确"));}
    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<ApiError> status(ResponseStatusException e) {return ResponseEntity.status(e.getStatusCode()).body(new ApiError("REQUEST_FAILED", e.getReason()));}
}
